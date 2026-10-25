"""Lets CLI members (Claude Code, Codex) use the company tools.

Boardroom listens on a random localhost port, protected by a random token. Each CLI agent is
started with a tiny MCP server (mcp_server.py) that forwards its tool calls here, tagged with
that agent's id, so a CEO running inside Claude Code can `delegate` just like an API CEO.
"""

from __future__ import annotations

import json
import os
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from boardroom import tools as T

APPROVE_TOOL = {
    "name": "approve",
    "description": "Asks the user whether a tool call may run (used by Claude Code itself).",
    "inputSchema": {"type": "object", "properties": {"tool_name": {"type": "string"},
                                                     "input": {"type": "object"}}},
}


class Bridge:
    def __init__(self, company):
        self.company = company
        self.token = secrets.token_urlsafe(24)
        bridge = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                if self.headers.get("authorization") != f"Bearer {bridge.token}":
                    return self._send(403, {"error": "bad token"})
                try:
                    body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))))
                except ValueError:
                    return self._send(400, {"error": "bad json"})
                if self.path == "/tools":
                    return self._send(200, {"tools": bridge.tools(body.get("agent", ""))})
                if self.path == "/call":
                    text, err = bridge.call(body.get("agent", ""), body.get("tool", ""),
                                            body.get("args") or {})
                    return self._send(200, {"text": text, "is_error": err})
                self._send(404, {"error": "not found"})

            def _send(self, code, obj):
                data = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def _tool_list(self, spec) -> list[T.Tool]:
        conn = self.company.connectors[spec.account]
        return self.company.company_tools_for(spec, native_subagents=conn.kind == "claude-code")

    def tools(self, agent_id: str) -> list[dict]:
        spec = self.company.live.get(agent_id)
        if spec is None:
            return []
        out = [{"name": t.name, "description": t.description, "inputSchema": t.parameters,
                "annotations": {"readOnlyHint": False, "destructiveHint": False,
                                "openWorldHint": False}}
               for t in self._tool_list(spec)]
        if self.company.autonomy == "ask":
            out.append(APPROVE_TOOL)
        return out

    def call(self, agent_id: str, tool: str, args: dict) -> tuple[str, bool]:
        spec = self.company.live.get(agent_id)
        if spec is None:
            return "error: this agent is no longer part of a running company", True
        if tool == "approve":
            return self._approve(spec, args), False
        allowed = {t.name: t for t in self._tool_list(spec)}
        if tool not in allowed:
            return f"error: {tool!r} isn't available to {agent_id}", True
        return T.call(allowed[tool], T.Ctx(self.company, spec), args)

    def _approve(self, spec, args: dict) -> str:
        name = args.get("tool_name", "?")
        inp = args.get("input") or {}
        what = inp.get("command") or inp.get("file_path") or inp.get("url") or json.dumps(inp)[:200]
        if self.company.approve(spec, f"{name}: {what}"):
            return json.dumps({"behavior": "allow", "updatedInput": inp})
        return json.dumps({"behavior": "deny", "message": "The user did not allow this."})

    def mcp_server(self, agent_id: str) -> dict:
        """How a CLI should start the MCP server for one agent: command, args, env."""
        pkg_parent = str(Path(__file__).resolve().parent.parent)
        pythonpath = os.pathsep.join(p for p in (pkg_parent, os.environ.get("PYTHONPATH")) if p)
        return {
            "command": sys.executable,
            "args": ["-m", "boardroom.mcp_server"],
            "env": {"BOARDROOM_BRIDGE": self.url, "BOARDROOM_TOKEN": self.token,
                    "BOARDROOM_AGENT": agent_id, "PYTHONPATH": pythonpath},
        }

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
