"""One run of the company in a project folder: the goal, any follow-ups to the CEO, the run log
and the report. Used by the terminal (cli.py) and the web UI (web.py) alike."""

from __future__ import annotations

import time
from pathlib import Path

from boardroom import org
from boardroom.company import Company
from boardroom.connectors.base import RunResult
from boardroom.events import Bus


class Session:
    def __init__(self, workspace: Path, settings: dict, accounts: dict, subscribers=(),
                 ask_user=None):
        problems = org.validate(settings, accounts)
        if problems:
            raise org.OrgError("\n".join(problems))
        self.workspace = Path(workspace).resolve()
        self.settings = settings
        self.run_dir = self.workspace / ".boardroom" / "runs" / time.strftime("%Y-%m-%d_%H%M%S")
        while self.run_dir.exists():   # two runs started in the same second
            self.run_dir = self.run_dir.with_name(self.run_dir.name + "-2")
        self.bus = Bus(self.run_dir / "events.jsonl")
        for fn in subscribers:
            self.bus.subscribe(fn)
        try:
            self.company = Company(settings, accounts, self.workspace, self.bus, ask_user=ask_user)
        except Exception:
            self.bus.close()
            raise
        self.started = time.time()
        self.turns: list[tuple[str, str]] = []
        self.ok = True
        self.finished = False

    def start(self, goal: str) -> None:
        s = self.settings
        self.bus.emit("run_start", None, goal=goal, workspace=str(self.workspace),
                      company=s["name"], autonomy=s["autonomy"], members=s["member"],
                      run=self.run_dir.name)
        for text in self.warnings():
            self.bus.emit("notice", None, text=text)

    def warnings(self) -> list[str]:
        out = []
        kinds = {c.kind for c in self.company.connectors.values()}
        if self.settings["autonomy"] != "full":
            if "codex" in kinds and self.settings["autonomy"] == "ask":
                out.append("Codex members can't ask you first: their commands stay inside the "
                           "project folder, without network.")
            if "gemini-cli" in kinds:
                out.append("Gemini CLI members can't ask you first, so they edit files but "
                           "don't run commands.")
            return out
        shell = self.company.shell
        if shell and kinds & {"anthropic", "openai-compat"}:
            out.append(f"Shell commands of API members run without asking, {shell.description}.")
        from boardroom.connectors.claude_code import sandbox_available
        if "claude-code" in kinds and not sandbox_available():
            out.append("Claude Code members can run any command without asking. Install "
                       "bubblewrap and socat to keep them sandboxed to this folder.")
        if "gemini-cli" in kinds:
            out.append("Gemini CLI members can run any command without asking (not sandboxed).")
        return out

    def send(self, text: str) -> RunResult:
        """Give the CEO the goal, or a follow-up. Blocks until the CEO reports."""
        if self.turns:
            self.bus.emit("notice", None, text="continuing with the CEO")
            self.bus.emit("user", None, text=text)
        res = self.company.run(text)
        self.ok = res.ok
        self.turns.append((text, res.text))
        return res

    def stop(self) -> None:
        self.company.stop_all()

    @property
    def stopped(self) -> bool:
        return self.company.stop.is_set()

    def finish(self) -> Path:
        if self.finished:
            return self.run_dir / "report.md"
        self.finished = True
        seconds = time.time() - self.started
        report = self.run_dir / "report.md"
        try:
            write_report(report, self.settings, self.turns, self.company.usage, seconds)
            self.bus.emit("run_end", None, ok=self.ok and not self.stopped, seconds=seconds,
                          usage=self.company.usage, report_path=pretty(report))
        finally:
            self.company.close()
            self.bus.close()
        return report


def write_report(path: Path, settings, turns, usage, seconds) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# {settings['name']}: run report", "",
             f"Finished {time.strftime('%Y-%m-%d %H:%M')} after "
             f"{int(seconds // 60)}m{int(seconds % 60):02d}s.", ""]
    for goal, text in turns:
        lines += ["## Asked", "", goal, "", "## CEO's report", "", text, ""]
    if usage:
        lines += ["## Tokens", "", "| member | input | output | estimated cost |", "|---|---|---|---|"]
        lines += [f"| {m} | {u['input']:,} | {u['output']:,} | "
                  f"{'$%.2f' % u['cost'] if u.get('cost') else '–'} |" for m, u in usage.items()]
        total = sum(u.get("cost") or 0 for u in usage.values())
        if total:
            lines += ["", f"Estimated API cost: ${total:.2f} (subscriptions not included; "
                          "your provider's bill is what counts)."]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def pretty(p: Path) -> str:
    try:
        return "./" + str(p.relative_to(Path.cwd()))
    except ValueError:
        return str(p)


def list_runs(workspace: Path) -> list[dict]:
    """Past runs in a project folder, newest first."""
    import json
    d = Path(workspace) / ".boardroom" / "runs"
    if not d.is_dir():
        return []
    out = []
    for r in sorted((p for p in d.iterdir() if p.is_dir()), reverse=True):
        info = {"name": r.name, "goal": "", "ok": None, "seconds": None}
        try:
            with open(r / "events.jsonl", encoding="utf-8") as f:
                for line in f:
                    ev = json.loads(line)
                    if ev["type"] == "run_start":
                        info["goal"] = ev.get("goal", "")
                    elif ev["type"] == "run_end":
                        info["ok"], info["seconds"] = ev.get("ok"), ev.get("seconds")
        except (OSError, ValueError):
            pass
        out.append(info)
    return out
