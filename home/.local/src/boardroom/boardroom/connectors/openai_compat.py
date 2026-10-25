"""Any API that speaks OpenAI's Chat Completions: OpenAI itself, DeepSeek, OpenRouter, Gemini,
Groq, Mistral, Together, xAI, and local servers like Ollama or LM Studio."""

from __future__ import annotations

import json
import uuid

from boardroom import catalog
from boardroom.connectors.base import (Connector, ConnectorError, Reply, ToolCall, api_key,
                                       http_json, parse_args)

# preset: (base_url, env var holding the key, models to offer if the API can't list them)
PRESETS = {
    "openai": ("https://api.openai.com/v1", "OPENAI_API_KEY", []),
    "deepseek": ("https://api.deepseek.com/v1", "DEEPSEEK_API_KEY", ["deepseek-v4-pro", "deepseek-flash"]),
    "openrouter": ("https://openrouter.ai/api/v1", "OPENROUTER_API_KEY", []),
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "GEMINI_API_KEY", []),
    "groq": ("https://api.groq.com/openai/v1", "GROQ_API_KEY", []),
    "mistral": ("https://api.mistral.ai/v1", "MISTRAL_API_KEY", []),
    "together": ("https://api.together.xyz/v1", "TOGETHER_API_KEY", []),
    "xai": ("https://api.x.ai/v1", "XAI_API_KEY", []),
    "ollama": ("http://localhost:11434/v1", None, []),
    "lmstudio": ("http://localhost:1234/v1", None, []),
}

LOCAL = {"ollama", "lmstudio"}


class OpenAICompatConnector(Connector):
    kind = "openai-compat"

    @property
    def base(self) -> str:
        url = self.cfg.get("base_url") or PRESETS.get(self.cfg.get("preset", ""), ("",))[0]
        if not url:
            raise ConnectorError(f"Account {self.name!r} has no base_url")
        return url.rstrip("/")

    def _headers(self) -> dict:
        key = api_key(self.cfg)
        if not key:
            if self.cfg.get("preset") in LOCAL or self.cfg.get("no_key"):
                return {}
            raise ConnectorError(f"No API key for account {self.name!r} "
                                 f"(set {self.cfg.get('key_env') or 'a key'})")
        return {"authorization": f"Bearer {key}"}

    def list_models(self) -> list[str]:
        j = http_json("GET", f"{self.base}/models", self._headers(), retries=1, timeout=30)
        ids = [m.get("id", "") for m in j.get("data", [])]
        # Gemini returns "models/gemini-2.5-pro"; the chat endpoint wants it without the prefix.
        ids = [i.removeprefix("models/") for i in ids if i]
        return sorted(i for i in ids if catalog.is_chat_model(i))

    def chat(self, model, system, messages, tools, max_tokens, stop=None) -> Reply:
        body = {"model": model, "messages": to_openai(system, messages)}
        if tools:
            body["tools"] = [{"type": "function", "function": {
                "name": t["name"], "description": t["description"], "parameters": t["parameters"]}}
                for t in tools]
        if self.cfg.get("max_tokens_param"):
            # Some servers need it; OpenAI's reasoning models reject max_tokens, so it is opt-in.
            body[self.cfg["max_tokens_param"]] = max_tokens
        j = http_json("POST", f"{self.base}/chat/completions", self._headers(), body, stop=stop)
        return from_openai(j)


def to_openai(system: str, messages: list[dict]) -> list[dict]:
    out = [{"role": "system", "content": system}]
    for m in messages:
        if m["role"] == "user":
            out.append({"role": "user", "content": m["content"]})
        elif m["role"] == "assistant":
            msg = {"role": "assistant", "content": m.get("content") or None}
            if m.get("tool_calls"):
                msg["tool_calls"] = [{"id": c.id, "type": "function", "function": {
                    "name": c.name, "arguments": c.bad_args or json.dumps(c.args)}}
                    for c in m["tool_calls"]]
            raw = m.get("raw") or {}
            if isinstance(raw, dict) and raw.get("reasoning_content"):
                # DeepSeek's thinking mode wants its reasoning back while a tool loop is running.
                msg["reasoning_content"] = raw["reasoning_content"]
            out.append(msg)
        elif m["role"] == "tool":
            out.append({"role": "tool", "tool_call_id": m["tool_call_id"], "content": m["content"]})
    return out


def from_openai(j: dict) -> Reply:
    choices = j.get("choices") or []
    if not choices:
        raise ConnectorError(f"The API sent no answer: {json.dumps(j)[:300]}")
    msg = choices[0].get("message") or {}
    calls = []
    for c in msg.get("tool_calls") or []:
        fn = c.get("function") or {}
        args, bad = parse_args(fn.get("arguments"))
        calls.append(ToolCall(c.get("id") or f"call_{uuid.uuid4().hex[:12]}",
                              fn.get("name", ""), args, bad))
    u = j.get("usage") or {}
    raw = {"reasoning_content": msg["reasoning_content"]} if msg.get("reasoning_content") else None
    # OpenAI reports cache hits in prompt_tokens_details; DeepSeek as prompt_cache_hit_tokens.
    cached = ((u.get("prompt_tokens_details") or {}).get("cached_tokens")
              or u.get("prompt_cache_hit_tokens") or 0)
    return Reply(msg.get("content") or "", calls, u.get("prompt_tokens", 0) or 0,
                 u.get("completion_tokens", 0) or 0, raw=raw, cached_tokens=cached)
