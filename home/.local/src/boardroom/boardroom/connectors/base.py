"""What every connector looks like, plus the shared HTTP helper.

There are two kinds of connectors:
  API connectors (anthropic, openai-compat) answer one model call at a time; Boardroom runs the
  agent loop and the tools itself (see agent.py).
  CLI connectors (claude-code, codex) run a whole agent in the vendor's own CLI, using the user's
  own login; Boardroom only hands them a task and the company tools (see bridge.py).
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass, field

USER_AGENT = "boardroom/0.1"


class ConnectorError(Exception):
    pass


@dataclass
class ToolCall:
    id: str
    name: str
    args: dict
    bad_args: str | None = None   # set when the model sent arguments that aren't valid JSON


@dataclass
class Reply:
    text: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    input_tokens: int = 0         # all input tokens, cached ones included
    output_tokens: int = 0
    raw: object = None            # provider message, echoed back verbatim on the next call
    cached_tokens: int = 0        # of input_tokens: read from the provider's cache (cheaper)
    cache_write_tokens: int = 0   # of input_tokens: written to the cache (Anthropic charges extra)


@dataclass
class RunResult:
    """What a CLI connector returns after running a whole agent."""
    text: str
    ok: bool = True
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0
    session: str | None = None    # to continue the conversation later


class Connector:
    kind = "?"
    is_cli = False
    append_only = False   # True: never edit earlier turns of a conversation (see anthropic_api.py)

    def __init__(self, name: str, cfg: dict):
        self.name = name
        self.cfg = cfg

    @property
    def max_parallel(self) -> int:
        return int(self.cfg.get("max_parallel", 4 if self.is_cli else 8))

    def list_models(self) -> list[str]:
        raise NotImplementedError

    def test(self) -> tuple[bool, str]:
        try:
            models = self.list_models()
        except ConnectorError as e:
            return False, str(e)
        return True, f"{len(models)} models"

    # API connectors
    def chat(self, model: str, system: str, messages: list[dict], tools: list[dict],
             max_tokens: int, stop=None) -> Reply:
        raise NotImplementedError


def api_key(cfg: dict) -> str | None:
    if cfg.get("key"):
        return cfg["key"]
    if cfg.get("key_env"):
        return os.environ.get(cfg["key_env"])
    return None


RETRY_STATUS = {408, 409, 429, 500, 502, 503, 504, 529}


def http_json(method: str, url: str, headers: dict, body: dict | None = None,
              timeout: float = 600, retries: int = 5, stop=None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    hdrs = {"content-type": "application/json", "user-agent": USER_AGENT, **headers}
    delay = 2.0
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            detail = _error_text(e)
            if e.code in RETRY_STATUS and attempt < retries:
                wait = _retry_after(e) or delay
                if stop is not None and stop.wait(wait):
                    raise ConnectorError("stopped")
                delay = min(delay * 2, 60)
                continue
            raise ConnectorError(f"HTTP {e.code} from {url}: {detail}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt < retries:
                if stop is not None and stop.wait(delay):
                    raise ConnectorError("stopped")
                delay = min(delay * 2, 60)
                continue
            reason = getattr(e, "reason", e)
            raise ConnectorError(f"Can't reach {url}: {reason}") from None
    raise ConnectorError("unreachable")


def _retry_after(e: urllib.error.HTTPError) -> float | None:
    try:
        return min(float(e.headers.get("retry-after", "")), 120)
    except (TypeError, ValueError):
        return None


def _error_text(e: urllib.error.HTTPError) -> str:
    try:
        raw = e.read().decode("utf-8", "replace")
    except Exception:
        return e.reason or ""
    try:
        j = json.loads(raw)
        err = j.get("error", j)
        if isinstance(err, dict):
            return err.get("message") or json.dumps(err)[:300]
        return str(err)[:300]
    except ValueError:
        return raw[:300]


def parse_args(raw) -> tuple[dict, str | None]:
    if isinstance(raw, dict):
        return raw, None
    if not raw:
        return {}, None
    try:
        v = json.loads(raw)
        return (v, None) if isinstance(v, dict) else ({}, raw)
    except ValueError:
        return {}, raw


def child_env(extra: dict | None = None) -> dict:
    """Environment for CLI subprocesses: without the markers of an enclosing Claude Code session."""
    env = {k: v for k, v in os.environ.items()
           if k not in ("CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_ENTRYPOINT",
                        "CLAUDE_CODE_SSE_PORT")}
    env.update(extra or {})
    return env
