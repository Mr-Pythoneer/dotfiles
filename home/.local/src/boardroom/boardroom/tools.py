"""Tools that API members use. (CLI members bring their own file and shell tools and only get
the company tools, through the bridge.)

Every tool returns text for the model. Problems come back as text too ("error: ..."), so the
model can correct itself instead of the run crashing.
"""

from __future__ import annotations

import fnmatch
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from boardroom.sandbox import clip

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".boardroom", ".mypy_cache",
             ".pytest_cache", "dist", "build", "target", ".next", ".cache"}


class ToolError(Exception):
    pass


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict
    fn: Callable          # fn(ctx, args) -> str
    summary: Callable     # summary(args) -> short text for the live view
    company_tool: bool = False

    def schema(self) -> dict:
        return {"name": self.name, "description": self.description, "parameters": self.parameters}


class Ctx:
    """What a tool can reach: the company, and which agent is calling."""

    def __init__(self, company, spec):
        self.company = company
        self.spec = spec

    @property
    def workspace(self) -> Path:
        return self.company.workspace

    def path(self, p: str) -> Path:
        if not isinstance(p, str) or not p:
            raise ToolError("path is missing")
        ws = self.workspace
        full = (Path(p) if os.path.isabs(p) else ws / p).resolve()
        if full != ws and ws not in full.parents:
            raise ToolError(f"{p} is outside the project folder ({ws})")
        return full

    def rel(self, full: Path) -> str:
        try:
            return str(full.relative_to(self.workspace)) or "."
        except ValueError:
            return str(full)


def _obj(props: dict, required: list[str]) -> dict:
    return {"type": "object", "properties": props, "required": required}


# --- file tools ---------------------------------------------------------------------------

def list_files(ctx: Ctx, a: dict) -> str:
    root = ctx.path(a.get("path") or ".")
    depth = int(a.get("depth") or 3)
    if not root.is_dir():
        raise ToolError(f"{a.get('path')} is not a folder")
    lines, limit = [], 400
    for dirpath, dirnames, filenames in os.walk(root):
        rel_depth = len(Path(dirpath).relative_to(root).parts)
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        if rel_depth >= depth:
            dirnames[:] = []
        for d in dirnames:
            lines.append(ctx.rel(Path(dirpath) / d) + "/")
        for f in sorted(filenames):
            lines.append(ctx.rel(Path(dirpath) / f))
        if len(lines) > limit:
            lines = lines[:limit] + [f"... (more than {limit} entries; list a subfolder)"]
            break
    return "\n".join(sorted(lines[:limit]) + lines[limit:]) or "(empty folder)"


def read_file(ctx: Ctx, a: dict) -> str:
    p = ctx.path(a.get("path"))
    if not p.is_file():
        raise ToolError(f"{a.get('path')} doesn't exist or isn't a file")
    data = p.read_bytes()
    if b"\0" in data[:8000]:
        return f"{ctx.rel(p)} is a binary file ({len(data)} bytes)"
    lines = data.decode("utf-8", "replace").splitlines()
    start = max(int(a.get("offset") or 1), 1)
    count = int(a.get("limit") or 1500)
    chunk = lines[start - 1: start - 1 + count]
    head = ""
    if start > 1 or start - 1 + count < len(lines):
        head = f"[lines {start}-{start + len(chunk) - 1} of {len(lines)}]\n"
    return head + clip("\n".join(chunk), 60_000)


def write_file(ctx: Ctx, a: dict) -> str:
    p = ctx.path(a.get("path"))
    content = a.get("content")
    if not isinstance(content, str):
        raise ToolError("content is missing")
    with ctx.company.path_lock(p):
        p.parent.mkdir(parents=True, exist_ok=True)
        existed = p.exists()
        with open(p, "w", encoding="utf-8", newline="") as f:
            f.write(content)
    return f"{'updated' if existed else 'created'} {ctx.rel(p)} ({len(content.splitlines())} lines)"


def edit_file(ctx: Ctx, a: dict) -> str:
    p = ctx.path(a.get("path"))
    old, new = a.get("old_string"), a.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str) or not old:
        raise ToolError("old_string and new_string are required (old_string can't be empty)")
    with ctx.company.path_lock(p):
        if not p.is_file():
            raise ToolError(f"{a.get('path')} doesn't exist (use write_file to create it)")
        with open(p, encoding="utf-8", newline="") as f:   # keep \r\n files as they are
            text = f.read()
        n = text.count(old)
        if n == 0:
            raise ToolError("old_string was not found in the file. Read the file again; it may "
                            "have changed, and the text must match exactly, including spaces.")
        if n > 1 and not a.get("replace_all"):
            raise ToolError(f"old_string appears {n} times. Add more surrounding text to make it "
                            "unique, or set replace_all to true.")
        with open(p, "w", encoding="utf-8", newline="") as f:
            f.write(text.replace(old, new) if a.get("replace_all") else text.replace(old, new, 1))
    return f"edited {ctx.rel(p)} ({n if a.get('replace_all') else 1} replacement)"


def search(ctx: Ctx, a: dict) -> str:
    pattern = a.get("pattern")
    if not pattern:
        raise ToolError("pattern is missing")
    root = ctx.path(a.get("path") or ".")
    glob = a.get("glob")
    rg = shutil.which("rg")
    if rg:
        cmd = [rg, "-n", "--no-heading", "--color", "never", "-m", "50", "-e", pattern]
        if glob:
            cmd += ["-g", glob]
        r = subprocess.run(cmd + [str(root)], capture_output=True, text=True, timeout=60,
                           stdin=subprocess.DEVNULL)
        out = r.stdout.replace(str(ctx.workspace) + os.sep, "")
        if r.returncode == 2:
            raise ToolError(r.stderr.strip()[:500])
    else:
        try:
            rx = re.compile(pattern)
        except re.error as e:
            raise ToolError(f"bad pattern: {e}")
        hits = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for f in filenames:
                if glob and not fnmatch.fnmatch(f, glob):
                    continue
                fp = Path(dirpath) / f
                try:
                    for i, line in enumerate(fp.read_text(encoding="utf-8").splitlines(), 1):
                        if rx.search(line):
                            hits.append(f"{ctx.rel(fp)}:{i}:{line}")
                except (UnicodeDecodeError, OSError):
                    continue
                if len(hits) > 500:
                    break
        out = "\n".join(hits)
    lines = out.splitlines()
    if len(lines) > 300:
        out = "\n".join(lines[:300]) + f"\n... ({len(lines) - 300} more matches)"
    return clip(out) or "no matches"


def run_shell(ctx: Ctx, a: dict) -> str:
    command = a.get("command")
    if not command:
        raise ToolError("command is missing")
    if not ctx.company.approve(ctx.spec, command):
        return "The user did not allow this command. Find another way, or explain in your report."
    timeout = min(float(a.get("timeout") or 300), 1800)
    code, out = ctx.company.shell.run(command, timeout=timeout)
    return f"exit code {code}\n{out}" if out else f"exit code {code} (no output)"


# --- company tools ------------------------------------------------------------------------

def delegate(ctx: Ctx, a: dict) -> str:
    items = a.get("assignments")
    if not isinstance(items, list) or not items:
        raise ToolError('assignments must be a list like [{"to": "worker-1", "task": "..."}]')
    return ctx.company.delegate(ctx.spec, items)


def spawn_subagents(ctx: Ctx, a: dict) -> str:
    tasks = a.get("tasks")
    if isinstance(tasks, str):
        tasks = [tasks]
    if not isinstance(tasks, list) or not tasks:
        raise ToolError("tasks must be a list of task descriptions")
    return ctx.company.spawn(ctx.spec, [str(t) for t in tasks])


def _first(s, n=70):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


FILE_TOOLS = [
    Tool("list_files", "List files and folders in the project (skips .git, node_modules and "
         "similar). Use it to get your bearings.",
         _obj({"path": {"type": "string", "description": "Folder to list, default the project root"},
               "depth": {"type": "integer", "description": "How many levels deep, default 3"}}, []),
         list_files, lambda a: a.get("path") or "."),
    Tool("read_file", "Read a text file. Long files come back in pieces; use offset/limit "
         "(line numbers, starting at 1) to read further.",
         _obj({"path": {"type": "string"}, "offset": {"type": "integer"},
               "limit": {"type": "integer"}}, ["path"]),
         read_file, lambda a: a.get("path", "")),
    Tool("write_file", "Create a file, or replace a whole file. Creates missing folders. For "
         "small changes to an existing file, edit_file is cheaper.",
         _obj({"path": {"type": "string"}, "content": {"type": "string"}}, ["path", "content"]),
         write_file, lambda a: a.get("path", "")),
    Tool("edit_file", "Replace exact text in a file. old_string must match the file exactly "
         "(including indentation) and be unique unless replace_all is true.",
         _obj({"path": {"type": "string"}, "old_string": {"type": "string"},
               "new_string": {"type": "string"}, "replace_all": {"type": "boolean"}},
              ["path", "old_string", "new_string"]),
         edit_file, lambda a: a.get("path", "")),
    Tool("search", "Search file contents with a regular expression. Returns file:line:text.",
         _obj({"pattern": {"type": "string"},
               "path": {"type": "string", "description": "Folder or file, default the project root"},
               "glob": {"type": "string", "description": 'Only files matching this, e.g. "*.py"'}},
              ["pattern"]),
         search, lambda a: a.get("pattern", "")),
]

SHELL_TOOL = Tool(
    "run_shell", "Run a shell command (bash) in the project folder and get its output and exit "
    "code. Use it to run programs, tests, builds and git. Commands must finish on their own: no "
    "interactive programs, and start servers in the background if you need them.",
    _obj({"command": {"type": "string"},
          "timeout": {"type": "number", "description": "Seconds, default 300, max 1800"}},
         ["command"]),
    run_shell, lambda a: _first(a.get("command"), 90))

DELEGATE_TOOL = Tool(
    "delegate", "Hand tasks to members of your company. All assignments in one call run in "
    "parallel; the call returns every member's report once they are all done. Members don't see "
    "your conversation, so each task must be self-contained.",
    _obj({"assignments": {"type": "array", "items": _obj({
        "to": {"type": "string", "description": 'A member id like "worker-2" or "debugger", or '
                                                '"any" for whichever worker is free'},
        "task": {"type": "string", "description": "The complete task"}}, ["to", "task"])}},
        ["assignments"]),
    delegate, lambda a: f"{len(a.get('assignments') or [])} tasks", company_tool=True)

SPAWN_TOOL = Tool(
    "spawn_subagents", "Start subagents that work in parallel on independent parts of your task. "
    "Each one gets only the task text you write and reports back when done; the call returns all "
    "reports together.",
    _obj({"tasks": {"type": "array", "items": {"type": "string"},
                    "description": "One complete, self-contained task per subagent"}}, ["tasks"]),
    spawn_subagents, lambda a: f"{len(a.get('tasks') or [])} subagents", company_tool=True)

ALL = {t.name: t for t in FILE_TOOLS + [SHELL_TOOL, DELEGATE_TOOL, SPAWN_TOOL]}


def call(tool: Tool, ctx: Ctx, args: dict) -> tuple[str, bool]:
    """Run a tool; returns (text, is_error)."""
    try:
        return tool.fn(ctx, args), False
    except ToolError as e:
        return f"error: {e}", True
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as e:
        return f"error: {type(e).__name__}: {e}", True
