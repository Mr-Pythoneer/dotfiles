"""Claude models through the Anthropic API, with an API key (pay per token)."""

from __future__ import annotations

from boardroom import catalog
from boardroom.connectors.base import (Connector, ConnectorError, Reply, ToolCall, api_key,
                                       http_json)

VERSION = "2023-06-01"


class AnthropicConnector(Connector):
    kind = "anthropic"
    # Current Claude models reject a conversation whose earlier turns were edited (their thinking
    # is tied to it), so the agent loop must never shorten old tool output for this connector.
    # They have a 1M-token context, which is plenty for one task.
    append_only = True

    @property
    def base(self) -> str:
        return self.cfg.get("base_url", "https://api.anthropic.com").rstrip("/")

    def _headers(self) -> dict:
        key = api_key(self.cfg)
        if not key:
            raise ConnectorError(f"No API key for account {self.name!r} "
                                 f"(set {self.cfg.get('key_env') or 'a key'})")
        return {"x-api-key": key, "anthropic-version": VERSION}

    def list_models(self) -> list[str]:
        j = http_json("GET", f"{self.base}/v1/models?limit=100", self._headers(), retries=1, timeout=30)
        return [m["id"] for m in j.get("data", []) if catalog.is_chat_model(m["id"])]

    def chat(self, model, system, messages, tools, max_tokens, stop=None) -> Reply:
        body = {
            "model": model,
            "max_tokens": max_tokens,
            # Cache the unchanging start (tools + system prompt), and let the API cache the rest
            # of the conversation automatically ("top-level" caching).
            "system": [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            "cache_control": {"type": "ephemeral"},
            "messages": to_anthropic(messages),
        }
        if self.cfg.get("effort"):
            body["output_config"] = {"effort": self.cfg["effort"]}   # low | medium | high | xhigh | max
        if tools:
            body["tools"] = [{"name": t["name"], "description": t["description"],
                              "input_schema": t["parameters"]} for t in tools]
        j = http_json("POST", f"{self.base}/v1/messages", self._headers(), body, stop=stop)
        return from_anthropic(j)


def to_anthropic(messages: list[dict]) -> list[dict]:
    out: list[dict] = []
    for m in messages:
        if m["role"] == "user":
            _append(out, "user", [{"type": "text", "text": m["content"]}])
        elif m["role"] == "assistant":
            if isinstance(m.get("raw"), list):
                blocks = m["raw"]   # keeps thinking blocks intact
            else:
                blocks = [{"type": "text", "text": m["content"]}] if m.get("content") else []
                blocks += [{"type": "tool_use", "id": c.id, "name": c.name, "input": c.args}
                           for c in m.get("tool_calls", [])]
            _append(out, "assistant", blocks or [{"type": "text", "text": "(no reply)"}])
        elif m["role"] == "tool":
            _append(out, "user", [{"type": "tool_result", "tool_use_id": m["tool_call_id"],
                                   "content": m["content"], "is_error": bool(m.get("is_error"))}])
    return out


def _append(out, role, blocks):
    if out and out[-1]["role"] == role:
        out[-1]["content"] = out[-1]["content"] + blocks
    else:
        out.append({"role": role, "content": list(blocks)})


def from_anthropic(j: dict) -> Reply:
    text, calls = [], []
    for b in j.get("content", []):
        if b.get("type") == "text":
            text.append(b["text"])
        elif b.get("type") == "tool_use":
            calls.append(ToolCall(b["id"], b["name"], b.get("input") or {}))
    stop = j.get("stop_reason")
    if stop == "refusal":
        details = j.get("stop_details") or {}
        why = details.get("explanation") or details.get("category") or "no reason given"
        text.append(f"(The model declined to continue: {why})")
        calls = []   # nothing more will happen in this turn
    elif stop == "max_tokens" and not calls:
        text.append("(The reply was cut off at the output limit.)")
    u = j.get("usage", {})
    cached = u.get("cache_read_input_tokens", 0) or 0
    written = u.get("cache_creation_input_tokens", 0) or 0
    tokens_in = (u.get("input_tokens", 0) or 0) + cached + written
    return Reply("\n".join(text), calls, tokens_in, u.get("output_tokens", 0), raw=j.get("content"),
                 cached_tokens=cached, cache_write_tokens=written)
