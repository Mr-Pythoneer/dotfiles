"""Gemini through Google's official Gemini CLI, using whatever login it has (a Google account,
Google AI Pro/Ultra, or a GEMINI_API_KEY). Boardroom never touches the login itself.

Each agent run is one headless `gemini` process in the project folder. The company tools come
from the Boardroom MCP server, which is added for that run only through a temporary settings
file (GEMINI_CLI_SYSTEM_SETTINGS_PATH), so the user's own Gemini settings are left alone.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
from pathlib import Path

from boardroom import prices
from boardroom.connectors.base import Connector, ConnectorError, RunResult
from boardroom.connectors.claude_code import summarize
from boardroom.connectors.cli_common import first_line, stream

# Boardroom's names for the CLI's model aliases ("pro" picks the best Pro model the account has).
ALIASES = {"gemini-pro": "pro", "gemini-flash": "flash", "gemini-flash-lite": "flash-lite",
           "gemini-auto": "auto"}
DEFAULT_MODELS = ["gemini-pro", "gemini-flash", "gemini-flash-lite"]

EXIT_CODES = {
    41: "not signed in. Run `gemini` once and sign in with Google (or set GEMINI_API_KEY)",
    42: "it got no prompt",
    44: "its sandbox is misconfigured",
    52: "its configuration is invalid (or yolo mode is disabled by an admin)",
    53: "it reached its turn limit",
    55: "the project folder isn't trusted",
}

# Gemini CLI can't ask anyone for approval when it runs headless:
#   full      yolo: edits and shell commands without asking (not sandboxed)
#   ask       auto_edit: file edits in the project folder; shell commands are refused
#   no-shell  auto_edit, the same
APPROVAL = {"full": "yolo", "ask": "auto_edit", "no-shell": "auto_edit"}


class GeminiCliConnector(Connector):
    kind = "gemini-cli"
    is_cli = True

    @property
    def binary(self) -> str:
        b = self.cfg.get("command") or shutil.which("gemini")
        if not b:
            raise ConnectorError("The Gemini CLI isn't installed. Install it with "
                                 "`npm install -g @google/gemini-cli`, then run `gemini` once to sign in")
        return b

    def list_models(self) -> list[str]:
        self.binary
        return list(DEFAULT_MODELS)

    def test(self) -> tuple[bool, str]:
        """Checks the login without spending a request (the CLI has no status command)."""
        try:
            self.binary
        except ConnectorError as e:
            return False, str(e)
        if os.environ.get("GEMINI_API_KEY"):
            return True, "using GEMINI_API_KEY"
        home = Path(os.environ.get("GEMINI_CLI_HOME") or Path.home()) / ".gemini"
        try:
            settings = json.loads((home / "settings.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            settings = {}
        auth = ((settings.get("security") or {}).get("auth") or {}).get("selectedType") \
            or settings.get("selectedAuthType")
        if auth == "oauth-personal" or (home / "oauth_creds.json").exists():
            return True, "signed in with Google"
        if auth:
            return True, f"set up ({auth})"
        return False, "not signed in; run `gemini` once and sign in with Google"

    def run_agent(self, company, spec, model, system, prompt, resume=None) -> RunResult:
        mcp = company.bridge.mcp_server(spec.id)
        settings = _system_settings()
        settings.setdefault("mcpServers", {})["boardroom"] = {
            "command": mcp["command"], "args": mcp["args"], "env": mcp["env"],
            "cwd": str(company.workspace),
            "timeout": 24 * 3600 * 1000,   # delegate can take a long time
            "trust": True,                 # company tools need no confirmation
        }
        tmp = Path(tempfile.mkdtemp(prefix="boardroom-gemini-"))
        settings_file = tmp / "settings.json"
        settings_file.write_text(json.dumps(settings), encoding="utf-8")
        os.chmod(settings_file, 0o600)

        argv = [self.binary, "--output-format", "stream-json", "--skip-trust",
                "--allowed-mcp-server-names", "boardroom",
                "--approval-mode", APPROVAL.get(company.autonomy, "auto_edit")]
        if model and model != "default":
            argv += ["--model", ALIASES.get(model, model)]
        if resume:
            argv += ["--resume", resume]
        argv += list(self.cfg.get("extra_args", []))
        # No separate system prompt option that keeps Gemini's own, so the role goes first.
        text = prompt if resume else f"{system}\n\n# Your task\n\n{prompt}"
        env = {"NO_BROWSER": "true", "GEMINI_CLI_SYSTEM_SETTINGS_PATH": str(settings_file)}

        p = _Parser(company, spec)
        try:
            with company.cli_slot(spec):
                code, err = stream(company, argv, text, p.on_event, company.workspace, env)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        r = p.result or {}
        stats = r.get("stats") or {}
        tin, tout = int(stats.get("input_tokens") or 0), int(stats.get("output_tokens") or 0)
        company.add_usage(spec, tin, tout, self._cost(stats, company))
        if company.stop.is_set() and code != 0:
            return RunResult("(stopped before finishing)", ok=False)
        failed = code != 0 or r.get("status") == "error"
        if failed:
            detail = ((r.get("error") or {}).get("message") or EXIT_CODES.get(code)
                      or (err.strip().splitlines()[-1] if err.strip() else f"exit code {code}"))
            company.bus.emit("error", spec.id, text=f"Gemini CLI failed: {detail}")
            return RunResult(p.text() or f"(Gemini CLI failed: {detail})", ok=False,
                             session=p.session)
        return RunResult(p.text() or "(no report)", input_tokens=tin, output_tokens=tout,
                         session=p.session)

    def _cost(self, stats: dict, company) -> float:
        if self.cfg.get("billing") != "api":
            return 0.0   # Google account / subscription: no per-token bill
        total = 0.0
        for name, u in (stats.get("models") or {}).items():
            total += prices.estimate(name, int(u.get("input_tokens") or 0),
                                     int(u.get("output_tokens") or 0), int(u.get("cached") or 0),
                                     overrides=company.settings.get("models"))
        return total


def _system_settings() -> dict:
    """Our settings file replaces the system-wide one for this run, so start from its content."""
    try:
        return json.loads(Path("/etc/gemini-cli/settings.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


class _Parser:
    """Turns `gemini --output-format stream-json` events into Boardroom events."""

    def __init__(self, company, spec):
        self.c, self.spec = company, spec
        self.session = None
        self.result = None
        self.parts: list[str] = []   # assistant text since the last tool call

    def text(self) -> str:
        return "".join(self.parts).strip()

    def on_event(self, ev: dict) -> None:
        t = ev.get("type")
        bus, me = self.c.bus, self.spec.id
        if t == "init":
            self.session = ev.get("session_id")
        elif t == "message" and ev.get("role") == "assistant":
            self.parts.append(ev.get("content") or "")
        elif t == "tool_use":
            if self.text():
                bus.emit("text", me, text=self.text())
            self.parts = []
            name = ev.get("tool_name") or ""
            if name.startswith("mcp_boardroom_"):
                return   # the company reports these itself
            params = ev.get("parameters") or {}
            summary = summarize(params, self.c.workspace) or first_line(params.get("dir_path") or "")
            bus.emit("tool", me, name=name, summary=summary)
        elif t == "error":
            bus.emit("notice", me, text=first_line(ev.get("message")))
        elif t == "result":
            self.result = ev
