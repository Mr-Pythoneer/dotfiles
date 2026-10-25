"""Running shell commands for API members.

Commands always start in the project folder. On Linux with bubblewrap installed (and
sandbox = "auto" or "bwrap"), they also run in a sandbox where the only writable places are the
project folder and a private /tmp, and secret folders (~/.ssh, API keys, ...) are hidden. Commands
can still use the network, so package installs work. Environment variables that look like secrets
(API keys, tokens) are never passed on, sandbox or not.
"""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

from boardroom.config import config_dir

MAX_OUTPUT = 20_000
SECRET_NAME = re.compile(r"API_?KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|^BOARDROOM_", re.I)
HIDDEN = [".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".password-store",
          ".config/gh", ".config/gcloud", ".local/share/keyrings"]


def bwrap_available() -> bool:
    return sys.platform.startswith("linux") and shutil.which("bwrap") is not None


def _bwrap_works() -> bool:
    try:
        r = subprocess.run(["bwrap", "--ro-bind", "/", "/", "true"],
                           capture_output=True, timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _bwrap_prefix(workspace: Path) -> list[str]:
    home = Path.home()
    args = ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
            "--tmpfs", "/tmp", "--die-with-parent"]
    for rel in HIDDEN:
        p = home / rel
        if p.is_dir():
            args += ["--tmpfs", str(p)]
    cfg = config_dir()
    if cfg.is_dir():
        args += ["--tmpfs", str(cfg)]
    cache = home / ".cache"
    if cache.is_dir():
        args += ["--tmpfs", str(cache)]       # writable, thrown away afterwards
    args += ["--bind", str(workspace), str(workspace), "--chdir", str(workspace)]
    return args


class Shell:
    def __init__(self, workspace: Path, mode: str = "auto", secret_env=()):
        self.workspace = workspace
        self.secret_env = set(secret_env)
        self.use_bwrap = mode == "bwrap" or (mode == "auto" and bwrap_available())
        if mode == "bwrap" and not bwrap_available():
            raise RuntimeError("sandbox = 'bwrap' but bubblewrap isn't installed")
        if self.use_bwrap and mode == "auto" and not _bwrap_works():
            self.use_bwrap = False   # e.g. user namespaces are switched off on this system
        self._procs: set[subprocess.Popen] = set()
        self._groups: set[int] = set()   # process groups that left something running

    @property
    def description(self) -> str:
        return "sandboxed (bubblewrap)" if self.use_bwrap else "not sandboxed"

    def env(self) -> dict:
        """The environment without API keys and other secrets."""
        env = {k: v for k, v in os.environ.items()
               if k not in self.secret_env and not SECRET_NAME.search(k)}
        if self.use_bwrap:
            env["npm_config_cache"] = "/tmp/.npm"
        return env

    def run(self, command: str, timeout: float = 300) -> tuple[int, str]:
        if sys.platform == "win32":
            argv, kw = command, {"shell": True}
        else:
            shell = shutil.which("bash") or "/bin/sh"
            argv = [shell, "-c", command]
            if self.use_bwrap:
                argv = _bwrap_prefix(self.workspace) + argv
            kw = {"start_new_session": True}
        # Output goes to a file, not a pipe: a server started in the background keeps a pipe
        # open forever, but doesn't stop us from seeing that the command itself has finished.
        with tempfile.TemporaryFile() as out:
            try:
                p = subprocess.Popen(argv, cwd=self.workspace, stdout=out, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, env=self.env(), **kw)
            except OSError as e:
                return 127, f"could not start the command: {e}"
            self._procs.add(p)
            note = ""
            try:
                code = p.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                self._kill_group(p.pid)
                p.wait()
                code, note = -1, f"\n[killed after {timeout:.0f}s timeout]"
            finally:
                self._procs.discard(p)
            if sys.platform != "win32" and _group_alive(p.pid):
                self._groups.add(p.pid)   # background processes; stopped when the run ends
            text = _read_clipped(out)
        return code, clip(text + note)

    def _kill_group(self, pgid: int) -> None:
        try:
            if sys.platform != "win32":
                os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass

    def kill_all(self) -> None:
        for p in list(self._procs):
            if sys.platform == "win32":
                p.kill()
            else:
                self._kill_group(p.pid)
        for g in list(self._groups):
            self._kill_group(g)
        self._groups.clear()


def _group_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
        return True
    except (ProcessLookupError, PermissionError, OSError):
        return False


def _read_clipped(f, limit: int = 4 * MAX_OUTPUT) -> str:
    size = f.seek(0, os.SEEK_END)
    f.seek(0)
    if size <= limit:
        data = f.read()
    else:
        data = f.read(limit // 2) + b"\n...\n"
        f.seek(size - limit // 2)
        data += f.read()
    return data.decode("utf-8", "replace")


def clip(s: str, limit: int = MAX_OUTPUT) -> str:
    if len(s) <= limit:
        return s
    head, tail = limit * 2 // 5, limit * 3 // 5
    return s[:head] + f"\n\n[... {len(s) - head - tail} characters cut ...]\n\n" + s[-tail:]
