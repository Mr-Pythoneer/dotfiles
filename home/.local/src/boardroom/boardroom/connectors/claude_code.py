"""Claude through the official Claude Code CLI, using whatever login Claude Code has (a Claude
Pro/Max subscription or a Console account). Boardroom never touches the login itself.

Each agent run is one `claude -p` process. The member gets Claude Code's own tools and its
native subagents; the company tools (delegate, ...) come from the Boardroom MCP server.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys

from boardroom.connectors.base import Connector, ConnectorError, RunResult
from boardroom.connectors.cli_common import dumps, first_line, rel, stream, text_of

# "fable" exists too, but needs extra access; add it with --models if your account has it.
DEFAULT_MODELS = ["opus", "sonnet", "haiku"]
SUBAGENT_TOOLS = {"Agent", "Task"}


def sandbox_available() -> bool:
    """Claude Code's own bash sandbox needs bubblewrap and socat on Linux."""
    if sys.platform == "darwin":
        return True
    if sys.platform.startswith("linux"):
        return bool(shutil.which("bwrap") and shutil.which("socat"))
    return False


class ClaudeCodeConnector(Connector):
    kind = "claude-code"
    is_cli = True

    @property
    def binary(self) -> str:
        b = self.cfg.get("command") or shutil.which("claude")
        if not b:
            raise ConnectorError("Claude Code isn't installed. Get it from "
                                 "https://claude.com/claude-code, then run: claude auth login")
        return b

    def list_models(self) -> list[str]:
        self.binary   # fails clearly when Claude Code is missing
        return list(DEFAULT_MODELS)

    def test(self) -> tuple[bool, str]:
        try:
            r = subprocess.run([self.binary, "auth", "status"], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                               timeout=30)
        except (ConnectorError, OSError, subprocess.TimeoutExpired) as e:
            return False, str(e)
        try:
            j = json.loads(r.stdout)
        except ValueError:
            return r.returncode == 0, first_line(r.stdout or r.stderr) or "unknown status"
        if not j.get("loggedIn"):
            return False, "not logged in; run: claude auth login"
        plan = j.get("subscriptionType")
        return True, f"logged in ({j.get('authMethod', '?')}{', ' + plan + ' plan' if plan else ''})"

    def permission_args(self, autonomy: str) -> list[str]:
        if autonomy == "ask":
            return ["--permission-mode", "acceptEdits",
                    "--permission-prompt-tool", "mcp__boardroom__approve"]
        if autonomy == "no-shell":
            return ["--permission-mode", "acceptEdits", "--disallowedTools", "Bash",
                    "--permission-prompts", "none"]
        # full: edits in the project folder, shell commands inside Claude Code's sandbox
        if sandbox_available() and not self.cfg.get("no_sandbox"):
            settings = {"sandbox": {"enabled": True, "autoAllowBashIfSandboxed": True}}
            return ["--permission-mode", "acceptEdits", "--settings", dumps(settings),
                    "--permission-prompts", "none"]
        return ["--permission-mode", "bypassPermissions"]

    def run_agent(self, company, spec, model, system, prompt, resume=None) -> RunResult:
        mcp = {"mcpServers": {"boardroom": company.bridge.mcp_server(spec.id)}}
        argv = [self.binary, "-p", "--output-format", "stream-json", "--verbose",
                "--model", model, "--append-system-prompt", system,
                "--mcp-config", dumps(mcp),
                *self.permission_args(company.autonomy),
                "--allowedTools", "mcp__boardroom__*"]
        if resume:
            argv += ["--resume", resume]
        elif spec.role != "ceo":
            argv += ["--no-session-persistence"]
        argv += list(self.cfg.get("extra_args", []))

        p = _Parser(company, spec)
        with company.cli_slot(spec):
            # The prompt goes through stdin: options like --allowedTools take several values
            # and would swallow a prompt placed after them.
            code, err = stream(company, argv, prompt, p.on_event, company.workspace,
                               {"MCP_TIMEOUT": "60000"})
        if p.result is None:
            if company.stop.is_set():
                return RunResult("(stopped before finishing)", ok=False)
            detail = err.strip().splitlines()[-1] if err.strip() else f"exit code {code}"
            company.bus.emit("error", spec.id, text=f"Claude Code failed: {detail}")
            return RunResult(f"(Claude Code failed: {detail})", ok=False)
        r = p.result
        tin, tout = _tokens(r)
        # With a subscription, Claude Code's cost figure is only what the API would have charged.
        cost = float(r.get("total_cost_usd") or 0) if self.cfg.get("billing") == "api" else 0.0
        company.add_usage(spec, tin, tout, cost)
        text = r.get("result") or "; ".join(r.get("errors") or []) or "(no report)"
        return RunResult(text.strip(), ok=not r.get("is_error") and r.get("subtype") == "success",
                         input_tokens=tin, output_tokens=tout, session=r.get("session_id"))


class _Parser:
    """Turns Claude Code's stream-json into Boardroom events."""

    def __init__(self, company, spec):
        self.c, self.spec = company, spec
        self.result = None
        self.pending_text = None   # the newest text; if nothing follows, it is the report
        self.subs: dict[str, str] = {}   # Agent tool_use id -> our subagent id
        self.n = 0

    def who(self, parent_tool_use_id) -> str:
        return self.subs.get(parent_tool_use_id, self.spec.id) if parent_tool_use_id else self.spec.id

    def flush(self):
        if self.pending_text:
            self.c.bus.emit("text", self.spec.id, text=self.pending_text)
            self.pending_text = None

    def on_event(self, ev: dict) -> None:
        t = ev.get("type")
        if t == "system" and ev.get("subtype") == "init":
            for s in ev.get("mcp_servers") or []:
                if s.get("name") == "boardroom" and s.get("status") not in ("connected", None):
                    self.c.bus.emit("notice", self.spec.id,
                                    text=f"company tools unavailable (MCP {s.get('status')})")
        elif t == "assistant":
            who = self.who(ev.get("parent_tool_use_id"))
            for b in (ev.get("message") or {}).get("content") or []:
                if b.get("type") == "text" and who == self.spec.id and b.get("text", "").strip():
                    self.flush()
                    self.pending_text = b["text"]
                elif b.get("type") == "tool_use":
                    if who == self.spec.id:
                        self.flush()
                    self.tool(who, b)
        elif t == "user":
            for b in (ev.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_result" \
                        and b.get("tool_use_id") in self.subs:
                    sub = self.subs[b["tool_use_id"]]
                    self.c.bus.emit("report", sub, to=self.spec.id,
                                    text=text_of(b.get("content")), ok=not b.get("is_error"))
        elif t == "result":
            self.result = ev

    def tool(self, who: str, b: dict) -> None:
        name, inp = b.get("name", ""), b.get("input") or {}
        if name.startswith("mcp__boardroom__"):
            return   # the company reports these itself
        if name in SUBAGENT_TOOLS:
            self.n += 1
            sub = f"{self.spec.id}.sub{self.n}"
            self.subs[b.get("id")] = sub
            task = inp.get("description") or inp.get("prompt") or ""
            self.c.bus.emit("spawn", who, to=sub, task=task)
            return
        self.c.bus.emit("tool", who, name=name, summary=summarize(inp, self.c.workspace))


def summarize(inp: dict, workspace) -> str:
    if "command" in inp:
        return first_line(inp["command"])
    for k in ("file_path", "notebook_path", "path"):
        if inp.get(k):
            return rel(inp[k], workspace)
    for k in ("pattern", "url", "query", "description", "skill"):
        if inp.get(k):
            return first_line(inp[k])
    return ""


def _tokens(r: dict) -> tuple[int, int]:
    """Tokens of the whole run, subagents included when Claude Code reports them."""
    mu = r.get("modelUsage")
    if isinstance(mu, dict) and mu:
        tin = tout = 0
        for u in mu.values():
            if isinstance(u, dict):
                tin += sum(int(u.get(k) or 0) for k in
                           ("inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"))
                tout += int(u.get("outputTokens") or 0)
        if tin or tout:
            return tin, tout
    u = r.get("usage") or {}
    tin = sum(int(u.get(k) or 0) for k in
              ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    return tin, int(u.get("output_tokens") or 0)
