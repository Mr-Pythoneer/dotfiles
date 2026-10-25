"""Everything that happens in a run is an event. Events go to the run's events.jsonl and to every
subscriber (the terminal view now, a web dashboard later).

Event types and their fields (all have "ts", "type" and "agent"):
  run_start   goal, workspace, members
  agent_start member, role, model, parent, task
  text        text                      something an agent said (not its final report)
  tool        name, summary             an agent used a tool
  delegate    to, task                  the CEO handed a task to a member
  spawn       to, task                  a member started a subagent
  report      to, text, ok              an agent finished and reported back
  usage       input, output, cost       tokens (and dollars, when known) of one model call or CLI run
  ask         command                   waiting for the user to allow a shell command
  notice      text                      something the user should know (no agent, or about one)
  error       text
  run_end     ok, report, seconds, usage
"""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path


class Bus:
    def __init__(self, log_path: Path | None = None):
        self._subs = []
        self._lock = threading.RLock()
        self._file = None
        if log_path:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            self._file = open(log_path, "a", encoding="utf-8")

    def subscribe(self, fn) -> None:
        self._subs.append(fn)

    def emit(self, type_: str, agent: str | None = None, **data) -> dict:
        ev = {"ts": round(time.time(), 3), "type": type_, "agent": agent, **data}
        with self._lock:
            if self._file:
                self._file.write(json.dumps(ev, ensure_ascii=False) + "\n")
                self._file.flush()
            for fn in self._subs:
                try:
                    fn(ev)
                except Exception:
                    pass
        return ev

    def hold(self):
        """Keep other threads from printing (used while asking the user a question)."""
        return self._lock

    def close(self) -> None:
        if self._file:
            self._file.close()
            self._file = None
