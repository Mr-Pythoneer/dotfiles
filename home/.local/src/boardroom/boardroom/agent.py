"""The agent loop for API members: ask the model, run the tools it calls, feed the results back,
until it answers without calling a tool. That answer is its report."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

from boardroom import catalog, prices
from boardroom import tools as T
from boardroom.connectors.base import ConnectorError, RunResult

# Rough size limit for the conversation; older tool output is dropped beyond it.
MAX_CONTEXT_CHARS = 500_000

OUT_OF_STEPS = ("You have used all the steps you have for this task. Don't call any more tools. "
                "Write your report now: what is done, what isn't, and what should happen next.")


class ApiAgent:
    def __init__(self, company, spec, system: str, tool_list: list[T.Tool]):
        self.company = company
        self.spec = spec
        self.system = system
        self.tools = {t.name: t for t in tool_list}
        self.schemas = [t.schema() for t in tool_list]
        self.messages: list[dict] = []
        account, self.model = spec.model_ref.split(":", 1)
        self.conn = company.connectors[account]
        self.ctx = T.Ctx(company, spec)

    def send(self, text: str) -> RunResult:
        c = self.company
        self.messages.append({"role": "user", "content": text})
        for _ in range(c.settings["max_steps"]):
            if c.stop.is_set():
                return RunResult("(stopped before finishing)", ok=False)
            try:
                reply = self._ask(self.schemas)
            except ConnectorError as e:
                if c.stop.is_set():
                    return RunResult("(stopped before finishing)", ok=False)
                c.bus.emit("error", self.spec.id, text=str(e))
                return RunResult(f"(failed: {e})", ok=False)
            self.messages.append({"role": "assistant", "content": reply.text,
                                  "tool_calls": reply.tool_calls, "raw": reply.raw})
            if not reply.tool_calls:
                return RunResult(reply.text.strip() or "(finished without a report)")
            if reply.text.strip():
                c.bus.emit("text", self.spec.id, text=reply.text)
            self.messages.extend(self._run_tools(reply.tool_calls))
            if not self.conn.append_only:
                self._trim()
        # Out of steps: one last call for a report.
        self.messages.append({"role": "user", "content": OUT_OF_STEPS})
        try:
            reply = self._ask(self.schemas)
        except ConnectorError as e:
            return RunResult(f"(ran out of steps, then failed: {e})", ok=False)
        self.messages.append({"role": "assistant", "content": reply.text,
                              "tool_calls": [], "raw": None})
        return RunResult((reply.text or "(ran out of steps)").strip(), ok=False)

    def _ask(self, schemas):
        c = self.company
        with c.slot(self.conn.name):
            reply = self.conn.chat(self.model, self.system, self.messages, schemas,
                                   c.settings["max_tokens"], stop=c.stop)
        cost = prices.estimate(self.model, reply.input_tokens, reply.output_tokens,
                               reply.cached_tokens, reply.cache_write_tokens,
                               c.settings.get("models"), family=catalog.family_of(self.model))
        c.add_usage(self.spec, reply.input_tokens, reply.output_tokens, cost)
        return reply

    def _run_tools(self, calls) -> list[dict]:
        def one(call):
            tool = self.tools.get(call.name)
            if tool is None:
                return f"error: there is no tool called {call.name!r}", True
            if call.bad_args is not None:
                return "error: the arguments were not valid JSON; send them again", True
            if not tool.company_tool:
                self.company.bus.emit("tool", self.spec.id, name=call.name,
                                      summary=tool.summary(call.args))
            return T.call(tool, self.ctx, call.args)

        if len(calls) == 1:
            results = [one(calls[0])]
        else:
            with ThreadPoolExecutor(max_workers=min(len(calls), 8)) as pool:
                results = list(pool.map(one, calls))
        return [{"role": "tool", "tool_call_id": call.id, "name": call.name,
                 "content": text, "is_error": err}
                for call, (text, err) in zip(calls, results)]

    def _trim(self) -> None:
        total = sum(len(m.get("content") or "") for m in self.messages)
        for m in self.messages:
            if total <= MAX_CONTEXT_CHARS:
                break
            if m["role"] == "tool" and len(m["content"]) > 200:
                total -= len(m["content"])
                m["content"] = "[old tool output removed to save space; run the tool again if needed]"
                total += len(m["content"])
