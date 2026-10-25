"""Running a vendor CLI as a subprocess and reading its JSON-lines output."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import threading
from collections import deque
from pathlib import Path

from boardroom.connectors.base import child_env


def stream(company, argv: list[str], stdin_text: str | None, on_event, cwd: Path,
           env_extra: dict | None = None) -> tuple[int, str]:
    """Run argv, call on_event(dict) for every JSON line on stdout. Returns (exit code, the
    last lines of stderr). Killed when the company stops."""
    kw = {"start_new_session": True} if sys.platform != "win32" else {}
    try:
        p = subprocess.Popen(argv, cwd=cwd, env=child_env(env_extra), text=True, bufsize=1,
                             encoding="utf-8", errors="replace",
                             stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)
    except OSError as e:
        return 127, f"could not start {argv[0]}: {e}"
    company.procs.add(p)
    err_tail: deque[str] = deque(maxlen=40)

    def drain():
        for line in p.stderr:
            err_tail.append(line.rstrip())

    t = threading.Thread(target=drain, daemon=True)
    t.start()
    try:
        if stdin_text is not None:
            try:
                p.stdin.write(stdin_text)
                p.stdin.close()
            except BrokenPipeError:
                pass
        for line in p.stdout:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            on_event(ev)
        p.wait()
    finally:
        company.procs.discard(p)
        if p.poll() is None:
            kill(p)
    t.join(timeout=2)
    for f in (p.stdout, p.stderr):
        f.close()
    return p.returncode, "\n".join(err_tail)


def kill(p: subprocess.Popen) -> None:
    try:
        if sys.platform != "win32":
            os.killpg(p.pid, signal.SIGTERM)
        else:
            p.terminate()
        p.wait(timeout=5)
    except (ProcessLookupError, PermissionError, OSError, subprocess.TimeoutExpired):
        try:
            p.kill()
        except OSError:
            pass


def rel(path: str, workspace: Path) -> str:
    try:
        return str(Path(path).resolve().relative_to(workspace))
    except (ValueError, OSError):
        return path


def first_line(s, n=90) -> str:
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def text_of(content) -> str:
    """Text of a tool_result's content, which may be a string or a list of blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def dumps(obj) -> str:
    return json.dumps(obj, ensure_ascii=False)
