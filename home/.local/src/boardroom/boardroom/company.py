"""The running company: hands tasks to members, starts subagents, and keeps everyone within the
limits (one task at a time per member, a few parallel calls per account, the token budget)."""

from __future__ import annotations

import os
import signal
import sys
import threading
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from boardroom import connectors, org, prompts
from boardroom import tools as T
from boardroom.agent import ApiAgent
from boardroom.connectors.base import ConnectorError, RunResult
from boardroom.sandbox import Shell


@dataclass
class Spec:
    """One agent at work: a member on a task, or a subagent."""
    id: str            # "worker-1", or "worker-1.sub2" for a subagent
    member: dict       # the member it belongs to (a subagent's is its parent's)
    role: str          # "ceo", "worker", "debugger", a custom role, or "subagent"
    model_ref: str     # account:model
    parent: str | None
    depth: int = 0

    @property
    def account(self) -> str:
        return self.model_ref.split(":", 1)[0]


class Company:
    def __init__(self, settings: dict, accounts: dict, workspace: Path, bus, ask_user=None):
        problems = org.validate(settings, accounts)
        if problems:
            raise org.OrgError("\n".join(problems))
        self.settings = settings
        self.workspace = Path(workspace).resolve()
        self.bus = bus
        self.autonomy = settings["autonomy"]
        self.ask_user = ask_user          # fn(question) -> answer, or None when nobody can answer
        self.members = {m["id"]: m for m in settings["member"]}
        self.ceo = next(m for m in settings["member"] if m["role"] == "ceo")
        self.roles = {k: {"description": v} for k, v in org.BUILTIN_ROLES.items()}
        for name, r in (settings.get("roles") or {}).items():
            self.roles[name] = {**self.roles.get(name, {}), **r}

        used = {m[k].split(":", 1)[0] for m in self.members.values()
                for k in ("model", "subagent_model") if m.get(k)}
        self.connectors = {a: connectors.make(a, accounts[a]) for a in sorted(used)}
        self.slots = {a: threading.Semaphore(c.max_parallel) for a, c in self.connectors.items()}
        self.member_locks = {mid: threading.Lock() for mid in self.members}
        self.load: Counter = Counter()
        self.usage: dict[str, dict] = {}
        self.stop = threading.Event()
        secrets = {a.get("key_env") for a in accounts.values() if a.get("key_env")}
        secrets |= set(connectors.KEY_ENV.values())
        self.shell = Shell(self.workspace, settings.get("sandbox", "auto"), secrets) \
            if self.autonomy != "no-shell" else None
        self.always_allow = False
        self.procs: set = set()            # running CLI subprocesses
        self.live: dict[str, Spec] = {}    # agents that are running right now, by id
        self._holding: set[str] = set()   # CLI agents that hold an account slot
        self._lock = threading.Lock()
        self._ask_lock = threading.Lock()
        self._path_locks: dict[str, threading.Lock] = {}
        self._subs: Counter = Counter()
        self._ceo_state = None
        self.bridge = None
        if any(c.is_cli for c in self.connectors.values()):
            from boardroom.bridge import Bridge
            self.bridge = Bridge(self)

    # --- running ----------------------------------------------------------------------------

    def run(self, goal: str) -> RunResult:
        """Give the CEO a goal. Call again to continue the same conversation."""
        spec = Spec("ceo", self.ceo, "ceo", self.ceo["model"], None)
        self.bus.emit("agent_start", "ceo", member="ceo", role="ceo",
                      model=_short(spec.model_ref), parent=None, task=goal)
        res = self._execute(spec, goal, keep=True)
        self.bus.emit("report", "ceo", to=None, text=res.text, ok=res.ok)
        return res

    def _execute(self, spec: Spec, task: str, keep: bool = False) -> RunResult:
        conn = self.connectors[spec.account]
        model = spec.model_ref.split(":", 1)[1]
        boss = "the CEO" if spec.role != "subagent" else spec.parent
        system = prompts.build(spec.role, spec.id, self.settings["name"], self.workspace,
                               self.autonomy, list(self.members.values()), self.roles, boss=boss)
        with self._lock:
            self.live[spec.id] = spec
        try:
            if conn.is_cli:
                resume = self._ceo_state if keep else None
                res = conn.run_agent(self, spec, model, system, task, resume=resume)
                if keep and res.session:   # a failed turn keeps the earlier conversation
                    self._ceo_state = res.session
                return res
            agent = self._ceo_state if keep and self._ceo_state else \
                ApiAgent(self, spec, system, self.tools_for(spec))
            if keep:
                self._ceo_state = agent
            return agent.send(task)
        except Exception as e:   # a bug or crash in one agent shouldn't take the company down
            self.bus.emit("error", spec.id, text=f"{type(e).__name__}: {e}")
            return RunResult(f"(crashed: {type(e).__name__}: {e})", ok=False)
        finally:
            with self._lock:
                self.live.pop(spec.id, None)

    def tools_for(self, spec: Spec) -> list[T.Tool]:
        out = list(T.FILE_TOOLS)
        if self.autonomy != "no-shell":
            out.append(T.SHELL_TOOL)
        return out + self.company_tools_for(spec)

    def company_tools_for(self, spec: Spec, native_subagents: bool = False) -> list[T.Tool]:
        out = []
        has_team = len(self.members) > 1
        if spec.role == "ceo" and has_team:
            out.append(T.DELEGATE_TOOL)
        if spec.depth < self.settings["max_depth"] and not native_subagents \
                and not (spec.role == "ceo" and has_team):
            out.append(T.SPAWN_TOOL)
        return out

    # --- company tools -----------------------------------------------------------------------

    def delegate(self, frm: Spec, items: list) -> str:
        if frm.role != "ceo":
            return "error: only the CEO hands out tasks; use spawn_subagents instead"
        jobs = []
        for it in items:
            it = it if isinstance(it, dict) else {}
            to, task = str(it.get("to", "")).strip(), str(it.get("task", "")).strip()
            mid = self._pick(to) if task else None
            if not task:
                jobs.append((to or "?", None, "error: the task is empty"))
            elif mid is None:
                team = ", ".join(self._team())
                jobs.append((to or "?", None, f"error: no member called {to!r}. Your team: {team}"))
            else:
                jobs.append((mid, task, None))
        with self._released(frm), ThreadPoolExecutor(max_workers=len(jobs)) as pool:
            futures = [pool.submit(self._member_task, mid, task, frm) if task else None
                       for mid, task, _ in jobs]
            out = []
            for (mid, task, err), fut in zip(jobs, futures):
                if fut is None:
                    out.append(f"## {mid}: not started\n{err}")
                    continue
                res = fut.result()
                out.append(f"## {mid}: {'done' if res.ok else 'did not finish'}\n{res.text}")
        return "\n\n".join(out)

    def _pick(self, to: str) -> str | None:
        with self._lock:
            if to in self._team():
                self.load[to] += 1
                return to
            if to.lower() in ("any", "worker", "workers", ""):
                pool = [m for m, v in self.members.items() if v["role"] == "worker"] or \
                       self._team()
                if not pool:
                    return None
                mid = min(pool, key=lambda m: (self.load[m], m))
                self.load[mid] += 1
                return mid
            return None

    def _team(self) -> list[str]:
        return [m for m, v in self.members.items() if v["role"] != "ceo"]

    def _member_task(self, mid: str, task: str, frm: Spec) -> RunResult:
        m = self.members[mid]
        spec = Spec(mid, m, m["role"], m["model"], frm.id)
        self.bus.emit("delegate", frm.id, to=mid, task=task)
        try:
            if not self._acquire(self.member_locks[mid]):
                return RunResult("(stopped before starting)", ok=False)
            try:
                self.bus.emit("agent_start", mid, member=mid, role=m["role"],
                              model=_short(spec.model_ref), parent=frm.id, task=task)
                res = self._execute(spec, task)
            finally:
                self.member_locks[mid].release()
        finally:
            with self._lock:
                self.load[mid] -= 1
        self.bus.emit("report", mid, to=frm.id, text=res.text, ok=res.ok)
        return res

    def spawn(self, frm: Spec, tasks: list[str]) -> str:
        if frm.depth >= self.settings["max_depth"]:
            return "error: subagents can't go any deeper here; do this yourself"
        limit = self.settings["max_subagents"]
        note = ""
        if len(tasks) > limit:
            note = f"\n\n(Only the first {limit} tasks were started; the limit is {limit} per call.)"
            tasks = tasks[:limit]
        ref = frm.member.get("subagent_model") or frm.member["model"]
        specs = []
        with self._lock:
            for _ in tasks:
                self._subs[frm.id] += 1
                specs.append(Spec(f"{frm.id}.sub{self._subs[frm.id]}", frm.member, "subagent",
                                  ref, frm.id, frm.depth + 1))

        def one(spec, task):
            self.bus.emit("spawn", frm.id, to=spec.id, task=task)
            self.bus.emit("agent_start", spec.id, member=frm.member["id"], role="subagent",
                          model=_short(ref), parent=frm.id, task=task)
            res = self._execute(spec, task)
            self.bus.emit("report", spec.id, to=frm.id, text=res.text, ok=res.ok)
            return res

        with self._released(frm), ThreadPoolExecutor(max_workers=len(specs)) as pool:
            results = list(pool.map(one, specs, tasks))
        return "\n\n".join(f"## {s.id}: {'done' if r.ok else 'did not finish'}\n{r.text}"
                           for s, r in zip(specs, results)) + note

    # --- limits and safety -------------------------------------------------------------------

    def _acquire(self, lock) -> bool:
        while not self.stop.is_set():
            if lock.acquire(timeout=0.5):
                return True
        return False

    @contextmanager
    def slot(self, account: str):
        """One of the account's parallel-call slots."""
        sem = self.slots[account]
        if not self._acquire(sem):
            raise _Stopped()
        try:
            yield
        finally:
            sem.release()

    @contextmanager
    def cli_slot(self, spec: Spec):
        """A CLI agent holds a slot for its whole run, but gives it back while it waits for
        delegated work, so parents waiting on children can never use up every slot."""
        with self.slot(spec.account):
            with self._lock:
                self._holding.add(spec.id)
            try:
                yield
            finally:
                with self._lock:
                    self._holding.discard(spec.id)

    @contextmanager
    def _released(self, spec: Spec):
        with self._lock:
            holding = spec.id in self._holding
        if not holding:
            yield
            return
        self.slots[spec.account].release()
        try:
            yield
        finally:
            self._acquire(self.slots[spec.account])

    def path_lock(self, path) -> threading.Lock:
        with self._lock:
            return self._path_locks.setdefault(str(path), threading.Lock())

    def approve(self, spec: Spec, command: str) -> bool:
        if self.autonomy == "full" or self.always_allow:
            return True
        if self.autonomy == "no-shell" or self.ask_user is None:
            return False
        with self._ask_lock:   # one question at a time
            if self.always_allow:
                return True
            if self.stop.is_set():
                return False
            self.bus.emit("ask", spec.id, command=command)
            answer = (self.ask_user("    allow? [y]es / [n]o / [a]lways this run: ")
                      or "").strip().lower()
            allowed = answer.startswith(("y", "a")) and not self.stop.is_set()
            if allowed and answer.startswith("a"):
                self.always_allow = True
            self.bus.emit("answer", spec.id, allowed=allowed, always=self.always_allow)
        return allowed

    def add_usage(self, spec: Spec, input_tokens: int, output_tokens: int, cost: float = 0.0):
        key = spec.member["id"]
        with self._lock:
            u = self.usage.setdefault(key, {"input": 0, "output": 0, "cost": 0.0})
            u["input"] += input_tokens
            u["output"] += output_tokens
            u["cost"] += cost
            total = sum(x["input"] + x["output"] for x in self.usage.values())
        self.bus.emit("usage", spec.id, input=input_tokens, output=output_tokens, cost=cost)
        budget = self.settings.get("token_budget") or 0
        if budget and total > budget and not self.stop.is_set():
            self.bus.emit("notice", None, text=f"Token budget of {budget:,} used up; stopping.")
            self.stop_all()

    def stop_all(self) -> None:
        self.stop.set()
        if self.shell:
            self.shell.kill_all()
        for p in list(self.procs):
            terminate_group(p)

    def close(self) -> None:
        self.stop_all()
        if self.bridge:
            self.bridge.close()


def terminate_group(p) -> None:
    """SIGTERM a CLI member and everything it started (it runs in its own process group)."""
    try:
        if sys.platform != "win32":
            os.killpg(p.pid, signal.SIGTERM)
        else:
            p.terminate()
    except (ProcessLookupError, PermissionError, OSError):
        pass


class _Stopped(ConnectorError):
    def __init__(self):
        super().__init__("stopped")


def _short(ref: str) -> str:
    account, model = ref.split(":", 1)
    return f"{model} · {account}"
