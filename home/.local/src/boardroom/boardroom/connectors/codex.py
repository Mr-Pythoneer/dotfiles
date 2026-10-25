"""GPT models through OpenAI's official Codex CLI, using whatever login Codex has (a ChatGPT
plan or an API key). Boardroom never touches the login itself.

Each agent run is one `codex exec` process, working in the project folder. Codex brings its own
shell and editing tools; the company tools come from the Boardroom MCP server.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from boardroom.config import _value as toml_value
from boardroom.connectors.base import Connector, ConnectorError, RunResult
from boardroom.connectors.cli_common import first_line, rel, stream


# `codex exec` can't ask anyone for approval, so autonomy maps onto Codex's own sandbox:
#   full      edits + commands in the project folder, with network
#   ask       edits + commands in the project folder, without network (Codex can't ask you)
#   no-shell  read-only: Codex can look, but not change files or run anything that writes
SANDBOX = {"full": "workspace-write", "ask": "workspace-write", "no-shell": "read-only"}


class CodexConnector(Connector):
    kind = "codex"
    is_cli = True

    @property
    def binary(self) -> str:
        b = self.cfg.get("command") or shutil.which("codex")
        if not b:
            raise ConnectorError("The Codex CLI isn't installed. Install it with "
                                 "`npm install -g @openai/codex`, then run: codex login")
        return b

    def list_models(self) -> list[str]:
        try:
            r = subprocess.run([self.binary, "debug", "models"], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                               timeout=60)
            models = json.loads(r.stdout).get("models", [])
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return ["default"]
        usable = [m for m in models if m.get("visibility") == "list" and m.get("slug")]
        usable.sort(key=lambda m: m.get("priority", 999))
        return [m["slug"] for m in usable] or ["default"]

    def test(self) -> tuple[bool, str]:
        try:
            r = subprocess.run([self.binary, "login", "status"], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                               timeout=30)
        except (ConnectorError, OSError, subprocess.TimeoutExpired) as e:
            return False, str(e)
        msg = first_line((r.stderr or r.stdout).strip().splitlines()[0] if (r.stderr or r.stdout).strip() else "")
        if r.returncode != 0:
            return False, (msg or "not logged in") + "; run: codex login"
        return True, msg.split(" - ")[0] or "logged in"

    def run_agent(self, company, spec, model, system, prompt, resume=None) -> RunResult:
        mcp = company.bridge.mcp_server(spec.id)
        fd, name = tempfile.mkstemp(prefix="boardroom-codex-", suffix=".txt")
        os.close(fd)
        out_file = Path(name)
        argv = [self.binary, "exec", "-C", str(company.workspace), "-s", SANDBOX[company.autonomy]]
        if resume:
            argv += ["resume", resume]
        argv += ["--json", "-o", str(out_file), "--skip-git-repo-check"]
        if model and model != "default":
            argv += ["-m", model]
        cfg = {
            "mcp_servers.boardroom.command": mcp["command"],
            "mcp_servers.boardroom.args": mcp["args"],
            "mcp_servers.boardroom.env": mcp["env"],
            "mcp_servers.boardroom.startup_timeout_sec": 60,
            "mcp_servers.boardroom.tool_timeout_sec": 86400,
            # exec never asks for approval, so company tools must be pre-approved
            "mcp_servers.boardroom.default_tools_approval_mode": "approve",
        }
        if company.autonomy == "full":
            cfg["sandbox_workspace_write.network_access"] = True
        for k, v in cfg.items():
            argv += ["-c", f"{k}={toml_value(v)}"]
        argv += list(self.cfg.get("extra_args", []))
        argv.append("-")   # the prompt comes from stdin
        # Codex has no separate system prompt option, so the role goes in front of the task.
        text = prompt if resume else f"{system}\n\n# Your task\n\n{prompt}"

        p = _Parser(company, spec)
        try:
            with company.cli_slot(spec):
                code, err = stream(company, argv, text, p.on_event, company.workspace)
            final = out_file.read_text(encoding="utf-8").strip() if out_file.exists() else ""
        finally:
            out_file.unlink(missing_ok=True)
        company.add_usage(spec, p.tokens_in, p.tokens_out)
        if company.stop.is_set() and code != 0:
            return RunResult("(stopped before finishing)", ok=False)
        if code != 0 or p.failed:
            detail = p.failed or (err.strip().splitlines()[-1] if err.strip() else f"exit code {code}")
            company.bus.emit("error", spec.id, text=f"Codex failed: {detail}")
            return RunResult(final or f"(Codex failed: {detail})", ok=False, session=p.thread)
        return RunResult(final or p.last_text or "(no report)", input_tokens=p.tokens_in,
                         output_tokens=p.tokens_out, session=p.thread)


class _Parser:
    """Turns `codex exec --json` events into Boardroom events."""

    def __init__(self, company, spec):
        self.c, self.spec = company, spec
        self.thread = None
        self.tokens_in = self.tokens_out = 0
        self.failed = None
        self.last_text = None

    def on_event(self, ev: dict) -> None:
        t = ev.get("type")
        bus, me = self.c.bus, self.spec.id
        if t == "thread.started":
            self.thread = ev.get("thread_id")
        elif t == "turn.completed":
            u = ev.get("usage") or {}
            self.tokens_in = int(u.get("input_tokens") or 0)
            self.tokens_out = int(u.get("output_tokens") or 0)
        elif t == "turn.failed":
            self.failed = (ev.get("error") or {}).get("message") or "turn failed"
        elif t == "error":
            bus.emit("notice", me, text=first_line(ev.get("message")))
        elif t in ("item.started", "item.completed"):
            item = ev.get("item") or {}
            kind = item.get("type")
            if kind == "command_execution" and t == "item.started":
                bus.emit("tool", me, name="shell", summary=first_line(item.get("command")))
            elif kind == "file_change" and t == "item.completed":
                paths = ", ".join(rel(c.get("path", ""), self.c.workspace)
                                  for c in item.get("changes") or [])
                bus.emit("tool", me, name="edit", summary=first_line(paths))
            elif kind == "mcp_tool_call" and t == "item.started" and item.get("server") != "boardroom":
                bus.emit("tool", me, name=f"{item.get('server')}.{item.get('tool')}", summary="")
            elif kind == "web_search" and t == "item.started":
                bus.emit("tool", me, name="web_search", summary=first_line(item.get("query")))
            elif kind == "agent_message" and t == "item.completed":
                if self.last_text:
                    bus.emit("text", me, text=self.last_text)
                self.last_text = item.get("text")
