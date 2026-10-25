"""How good is a model? A rough guess from its name, used to hand out roles automatically.

Every model gets a tier:
  frontier  the strongest models; good CEOs
  strong    capable workhorses; good workers and debuggers
  fast      cheap and quick; good subagents
and a score (0-100) that orders models inside a tier.

Names change faster than code, so this is only a heuristic. Override any model in company.toml:
  [models."some-new-model"]
  tier = "frontier"
  score = 93
"""

from __future__ import annotations

import re
from dataclasses import dataclass

TIERS = ("frontier", "strong", "fast")
TIER_RANK = {t: i for i, t in enumerate(TIERS)}  # lower is better


@dataclass(frozen=True)
class ModelInfo:
    name: str
    family: str   # who made the model (anthropic, openai, deepseek, google, ...), not who serves it
    tier: str
    score: float

    @property
    def label(self) -> str:
        return f"{self.tier} {self.score:.0f}"


FAMILIES = [
    ("anthropic", r"claude|opus|sonnet|haiku|fable"),
    ("openai", r"gpt|chatgpt|(^|[/-])o\d|codex"),
    ("deepseek", r"deepseek"),
    ("google", r"gemini|gemma"),
    ("xai", r"grok"),
    ("meta", r"llama"),
    ("qwen", r"qwen|qwq"),
    ("mistral", r"mistral|mixtral|codestral|magistral|devstral|ministral"),
    ("moonshot", r"kimi|moonshot"),
    ("zhipu", r"glm"),
]

# (pattern, tier, base score). The first match wins, so specific patterns come first.
RULES = [
    (r"opus", "frontier", 95),
    (r"fable", "frontier", 94),
    (r"sonnet", "strong", 82),
    (r"haiku", "fast", 62),
    (r"(gpt|o\d)[\w.-]*-pro\b", "frontier", 97),
    # OpenAI's sizes since GPT-5.6: astra (top) > sol > terra > luna (small)
    (r"gpt-[\w.-]*astra", "frontier", 97),
    (r"gpt-[\w.-]*terra", "strong", 84),
    (r"gpt-[\w.-]*luna", "fast", 66),
    (r"gpt-oss-(120|1\d\d)b", "strong", 72),
    (r"gpt-oss", "fast", 55),
    (r"nano", "fast", 50),
    (r"flash-lite|lite\b", "fast", 55),
    (r"gpt-\d[\w.-]*-mini|o\d-mini", "fast", 66),
    (r"gpt-\d[\w.-]*-codex", "frontier", 90),
    (r"chat-latest", "strong", 80),
    (r"gpt-([5-9]|\d\d)", "frontier", 92),
    (r"gpt-4\.1", "strong", 72),
    (r"gpt-4o|gpt-4", "strong", 70),
    (r"gpt-3", "fast", 40),
    (r"(^|[/-])o[134]\b", "strong", 84),
    (r"deepseek.*pro", "strong", 82),
    (r"deepseek.*flash", "fast", 68),
    (r"deepseek.*(reasoner|r1)", "strong", 78),
    (r"deepseek.*(chat|v3|v4)", "strong", 75),
    (r"deepseek", "strong", 70),
    (r"gemini[\w.-]*pro", "frontier", 90),
    (r"gemini[\w.-]*flash", "fast", 68),
    (r"gemma", "fast", 50),
    (r"grok[\w.-]*(mini|fast)", "fast", 65),
    (r"grok", "strong", 85),
    (r"kimi|moonshot|glm|qwen3-coder|qwen3-max", "strong", 78),
    (r"\b(70|72|110|123|235|405|480|671)b\b|large", "strong", 70),
    (r"\b(\d|1\d)b\b|small|tiny", "fast", 45),
]

# Model names that aren't chat models (embeddings, speech, images...). Hidden from model lists.
NOT_CHAT = re.compile(
    r"embed|whisper|tts|dall-e|image|audio|realtime|moderation|transcribe|search|babbage|davinci"
    r"|sora|computer-use|rerank|guard|vision-preview|instruct$",
    re.I,
)

ALIASES = {"opus", "sonnet", "haiku", "fable", "default"}


def family_of(name: str) -> str:
    n = name.lower()
    for fam, pat in FAMILIES:
        if re.search(pat, n):
            return fam
    return "other"


def _version(name: str) -> float:
    """Pull a version like 5.5 out of claude-opus-5-5, gpt-5.6, gemini-2.5-pro, deepseek-v3.2."""
    n = re.sub(r"\d{8}|\d{4}-\d{2}-\d{2}", "", name.lower())  # drop date stamps
    m = re.search(r"(?<![\d.])(\d{1,2})(?:[.-](\d))?(?![\d])(?!b\b)", n)
    if not m:
        return 0.0
    major, minor = int(m.group(1)), int(m.group(2) or 0)
    return major + minor / 10 if major < 20 else 0.0


def classify(name: str, overrides: dict | None = None) -> ModelInfo:
    n = name.lower().split("/")[-1]  # openrouter-style "anthropic/claude-sonnet-5"
    fam = family_of(name)
    tier, score = "strong", 60.0
    for pat, t, s in RULES:
        if re.search(pat, n):
            tier, score = t, float(s)
            break
    # A bare alias ("opus") always points at the newest model of that line.
    score += 4.5 if n in ALIASES else min(_version(n), 9) * 0.5
    o = (overrides or {}).get(name) or {}
    tier = o.get("tier", tier) if o.get("tier") in TIERS else tier
    score = float(o.get("score", score))
    return ModelInfo(name=name, family=o.get("family", fam), tier=tier, score=score)


def is_chat_model(name: str) -> bool:
    return not NOT_CHAT.search(name)
