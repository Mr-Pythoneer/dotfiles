"""Connectors: how Boardroom talks to each kind of AI account."""

from __future__ import annotations

from boardroom.connectors.anthropic_api import AnthropicConnector
from boardroom.connectors.base import Connector, ConnectorError
from boardroom.connectors.claude_code import ClaudeCodeConnector
from boardroom.connectors.codex import CodexConnector
from boardroom.connectors.gemini_cli import GeminiCliConnector
from boardroom.connectors.openai_compat import PRESETS, OpenAICompatConnector

KINDS = {
    "claude-code": ClaudeCodeConnector,
    "codex": CodexConnector,
    "gemini-cli": GeminiCliConnector,
    "anthropic": AnthropicConnector,
    "openai-compat": OpenAICompatConnector,
}

# What `boardroom connect <provider>` understands: provider -> (kind, default account name)
PROVIDERS = {
    "claude-code": ("claude-code", "claude"),
    "claude": ("claude-code", "claude"),
    "codex": ("codex", "chatgpt"),
    "chatgpt": ("codex", "chatgpt"),
    "gemini-cli": ("gemini-cli", "google"),
    "anthropic": ("anthropic", "anthropic"),
    **{p: ("openai-compat", p) for p in PRESETS},
    "custom": ("openai-compat", "custom"),
}

KEY_ENV = {"anthropic": "ANTHROPIC_API_KEY", **{p: v[1] for p, v in PRESETS.items() if v[1]}}


def make(name: str, cfg: dict) -> Connector:
    cls = KINDS.get(cfg.get("kind", ""))
    if cls is None:
        raise ConnectorError(f"Account {name!r} has unknown kind {cfg.get('kind')!r} "
                             f"(known: {', '.join(KINDS)})")
    return cls(name, cfg)


__all__ = ["Connector", "ConnectorError", "KINDS", "PROVIDERS", "KEY_ENV", "PRESETS", "make"]
