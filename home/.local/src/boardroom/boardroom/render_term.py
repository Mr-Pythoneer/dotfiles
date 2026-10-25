"""The live terminal view of a run: one line per event, a colour per member."""

from __future__ import annotations

import os
import shutil
import sys
import time

PALETTE = [45, 114, 177, 75, 215, 150, 211, 117, 186, 141]   # 256-colour codes for workers
FIXED = {"ceo": 220, "debugger": 204}


def use_color(stream) -> bool:
    return stream.isatty() and not os.environ.get("NO_COLOR") and os.environ.get("TERM") != "dumb"


class Style:
    def __init__(self, on: bool):
        self.on = on

    def c(self, code: int, s: str, bold=False) -> str:
        if not self.on:
            return s
        return f"\033[{'1;' if bold else ''}38;5;{code}m{s}\033[0m"

    def dim(self, s: str) -> str:
        return f"\033[2m{s}\033[0m" if self.on else s

    def bold(self, s: str) -> str:
        return f"\033[1m{s}\033[0m" if self.on else s

    def red(self, s: str) -> str:
        return self.c(203, s, bold=True)

    def green(self, s: str) -> str:
        return self.c(114, s)


def display_name(agent_id: str | None) -> str:
    if not agent_id:
        return ""
    if agent_id == "ceo":
        return "CEO"
    if "." in agent_id:
        member, *subs = agent_id.split(".")
        return f"{display_name(member)} ↳ {subs[-1]}"
    return agent_id


def one_line(s: str, width: int) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= width else s[: max(width - 1, 0)] + "…"


class TermRenderer:
    WHO = 24

    def __init__(self, stream=None, color: bool | None = None, verbose: bool = False):
        self.out = stream or sys.stdout
        self.st = Style(use_color(self.out) if color is None else color)
        self.verbose = verbose
        self.colors: dict[str, int] = {}
        self.models: dict[str, str] = {}
        self.held: list | None = None

    def color_of(self, agent_id: str) -> int:
        member = agent_id.split(".")[0]
        if member not in self.colors:
            self.colors[member] = FIXED.get(member) or PALETTE[len(self.colors) % len(PALETTE)]
        return self.colors[member]

    def who(self, agent_id, to=None) -> str:
        name = display_name(agent_id)
        if to:
            name = f"{name} → {display_name(to)}"
        pad = " " * max(self.WHO - len(name), 1)
        if not agent_id:
            return name + pad
        parts = self.st.c(self.color_of(agent_id), display_name(agent_id), bold="." not in agent_id)
        if to:
            parts += self.st.dim(" → ") + self.st.c(self.color_of(to), display_name(to))
        return parts + pad

    def line(self, agent, body, to=None, ts=None):
        stamp = self.st.dim(time.strftime("%H:%M:%S", time.localtime(ts or time.time())))
        self.out.write(f"{stamp}  {self.who(agent, to)}{body}\n")
        self.out.flush()

    def width(self) -> int:
        return max(shutil.get_terminal_size((100, 20)).columns - 10 - self.WHO, 20)

    def __call__(self, ev: dict) -> None:
        # While the user answers a question, hold everything else back so it doesn't get lost.
        if ev["type"] == "ask":
            self.held = []
        elif ev["type"] == "answer":
            self.show(ev)
            held, self.held = self.held, None
            for e in held or []:
                self.show(e)
            return
        elif self.held is not None:
            self.held.append(ev)
            return
        self.show(ev)

    def show(self, ev: dict) -> None:
        t, a, w = ev["type"], ev.get("agent"), self.width()
        st = self.st
        if t == "run_start":
            self.out.write(st.bold(f"\n{ev.get('company', 'Boardroom')}") +
                           st.dim(f"  ·  {ev['workspace']}  ·  autonomy: {ev.get('autonomy')}\n"))
            self.out.write(st.dim("Goal: ") + one_line(ev["goal"], w + self.WHO) + "\n\n")
        elif t == "agent_start":
            self.models[a] = ev.get("model", "")
            if not ev.get("parent"):
                self.line(a, st.dim(f"started · {ev.get('model', '')}"), ts=ev["ts"])
        elif t == "text":
            if self.verbose or not ev.get("minor"):
                self.line(a, st.dim(one_line(ev["text"], w)), ts=ev["ts"])
        elif t == "tool":
            self.line(a, "⚙ " + one_line(f"{ev['name']} {ev.get('summary', '')}".strip(), w - 2),
                      ts=ev["ts"])
        elif t == "delegate":
            self.line(a, '"' + one_line(ev["task"], w - 2) + '"', to=ev["to"], ts=ev["ts"])
        elif t == "spawn":
            # "worker-2 ↳ sub1" already says whose subagent it is
            self.line(ev["to"], st.dim("new: ") + '"' + one_line(ev["task"], w - 7) + '"', ts=ev["ts"])
        elif t == "report":
            to = ev.get("to")
            if a == "ceo" and not to:
                return   # the final report is printed in full after the run
            if to and a.startswith(to + "."):
                to = None   # a subagent reporting to its own parent
            mark = st.green("✓") if ev.get("ok", True) else st.red("✗")
            self.line(a, f"{mark} " + one_line(ev.get("text", ""), w - 2), to=to, ts=ev["ts"])
        elif t == "ask":
            self.line(a, st.c(220, "? wants to run: ") + one_line(ev["command"], w - 16), ts=ev["ts"])
        elif t == "answer":
            word = "allowed" if ev.get("allowed") else "not allowed"
            if ev.get("always"):
                word += " (and everything else this run)"
            self.line(a, st.dim(word), ts=ev["ts"])
        elif t == "user":
            self.line(None, st.bold("You: ") + one_line(ev["text"], w), ts=ev["ts"])
        elif t == "notice":
            if a:
                self.line(a, st.c(220, one_line(ev["text"], w)), ts=ev["ts"])
            else:
                stamp = st.dim(time.strftime("%H:%M:%S", time.localtime(ev["ts"])))
                self.out.write(f"{stamp}  {st.c(220, one_line(ev['text'], w + self.WHO))}\n")
                self.out.flush()
        elif t == "error":
            self.line(a, st.red("error: ") + one_line(ev["text"], w - 7), ts=ev["ts"])
        elif t == "usage" and self.verbose:
            self.line(a, st.dim(f"tokens in {ev.get('input', 0)} out {ev.get('output', 0)}"), ts=ev["ts"])
        elif t == "run_end":
            self.summary(ev)

    def summary(self, ev: dict) -> None:
        st = self.st
        mins, secs = divmod(int(ev.get("seconds", 0)), 60)
        status = st.green("done") if ev.get("ok") else st.red("stopped")
        parts = []
        for member, u in (ev.get("usage") or {}).items():
            tok = u.get("input", 0) + u.get("output", 0)
            s = f"{display_name(member)} {human(tok)}"
            if u.get("cost"):
                s += f" (${u['cost']:.2f})"
            parts.append(s)
        self.out.write(f"\n──── {status} in {mins}m{secs:02d}s")
        if parts:
            self.out.write(st.dim(" · tokens: " + ", ".join(parts)))
        total = sum(u.get("cost") or 0 for u in (ev.get("usage") or {}).values())
        if total:
            self.out.write(st.dim(f" · about ${total:.2f}"))
        if ev.get("report_path"):
            self.out.write(st.dim(f"\n     report: {ev['report_path']}"))
        self.out.write("\n")
        self.out.flush()


def human(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.0f}k"
    return str(n)
