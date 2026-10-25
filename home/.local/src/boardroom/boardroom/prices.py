"""What API calls cost, roughly. Used only to show estimates; your provider's bill is what counts.

Prices are US dollars per million tokens: (input, output, cached input). Cached input is what a
cache hit costs; when a provider doesn't list one, cache hits are priced as normal input. Writing
to Anthropic's cache costs 1.25x the input price.

Prices change. Correct or add a model in company.toml:
  [models."my-model"]
  price_in = 1.25       # per million input tokens
  price_out = 10.0      # per million output tokens
  price_cached = 0.125  # optional: per million cached input tokens

Subscriptions used through Claude Code or Codex cost nothing extra per token, so their members
show tokens only (set billing = "api" on a Claude Code account that uses a Console API key, to
count the cost Claude Code reports).
"""

from __future__ import annotations

PRICES_AS_OF = "2026-10-10"   # checked on the providers' pricing pages that day

# model id: (input, output, cached input or None)
PRICES: dict[str, tuple[float, float, float | None]] = {
    # Anthropic (platform.claude.com pricing)
    "claude-fable-5-1": (10.0, 50.0, 0.25),
    "claude-fable-5": (10.0, 50.0, None),
    "claude-opus-5-5": (4.0, 20.0, 0.20),
    "claude-opus-5": (5.0, 25.0, None),
    "claude-opus-4-8": (5.0, 25.0, None),
    "claude-opus-4-7": (5.0, 25.0, None),
    "claude-opus-4-6": (5.0, 25.0, None),
    "claude-sonnet-5-5": (2.0, 10.0, 0.20),
    "claude-sonnet-5": (2.0, 10.0, None),
    "claude-sonnet-4-6": (3.0, 15.0, None),
    "claude-haiku-5-5": (0.10, 0.50, None),
    "claude-haiku-4-5": (1.0, 5.0, None),
    # OpenAI (developers.openai.com/api/docs/pricing; standard tier, up to 272K input)
    "gpt-6-astra": (10.0, 50.0, 1.0),
    "gpt-6.1-sol": (2.0, 10.0, 0.10),
    "gpt-6-sol": (2.0, 10.0, 0.20),
    "gpt-6-luna": (0.10, 0.50, 0.01),
    "gpt-5.6-sol": (4.0, 20.0, 0.40),      # promotional price, "at least through 2026-11-21"
    "gpt-5.6-terra": (2.0, 12.0, 0.20),
    "gpt-5.6-luna": (0.20, 1.20, 0.02),
    "gpt-5.5": (5.0, 30.0, 0.50),
    "gpt-5.5-pro": (30.0, 180.0, None),
    "gpt-5.4": (2.5, 15.0, 0.25),
    "gpt-5.4-pro": (30.0, 180.0, None),
    "gpt-5.4-mini": (0.75, 4.50, 0.075),
    "gpt-5.4-nano": (0.20, 1.25, 0.02),
    "gpt-5.3-codex": (1.75, 14.0, 0.175),
    "gpt-5.2": (1.75, 14.0, 0.175),
    "gpt-5.2-pro": (21.0, 168.0, None),
    "gpt-5.1": (1.25, 10.0, 0.125),
    "gpt-5": (1.25, 10.0, 0.125),
    "gpt-5-mini": (0.25, 2.0, 0.025),
    "gpt-5-nano": (0.05, 0.40, 0.005),
    "gpt-5-pro": (15.0, 120.0, None),
    "o3": (2.0, 8.0, 0.50),
    "o3-pro": (20.0, 80.0, None),
    "o3-mini": (1.10, 4.40, 0.55),
    "o4-mini": (1.10, 4.40, 0.275),
    # DeepSeek (api-docs.deepseek.com/quick_start/pricing; peak hours; off-peak is half)
    "deepseek-v4-pro": (1.32, 3.96, 0.044),
    "deepseek-flash": (0.30, 1.20, 0.006),
    "deepseek-v4-flash": (0.30, 1.20, 0.006),
    # Google (ai.google.dev/gemini-api/docs/pricing; paid tier, up to 200K input)
    "gemini-3.1-pro-preview": (2.0, 12.0, 0.20),
    "gemini-2.5-pro": (1.25, 10.0, 0.125),
    "gemini-3.8-flash": (0.75, 3.75, 0.075),   # doubles on 2027-01-01
    "gemini-3.6-flash": (0.75, 3.75, 0.075),   # doubles on 2027-01-01
    "gemini-3-flash-preview": (0.50, 3.0, 0.05),
    "gemini-2.5-flash": (0.30, 2.50, 0.03),
    "gemini-3.5-flash-lite": (0.30, 2.50, 0.03),
    "gemini-3.1-flash-lite": (0.25, 1.50, 0.025),
    "gemini-2.5-flash-lite": (0.10, 0.40, 0.01),
    # xAI (docs.x.ai/developers/models; up to 200K input)
    "grok-4.7": (2.0, 6.0, 0.50),
    "grok-4.6": (2.0, 6.0, 0.50),
    "grok-4.5": (2.0, 6.0, 0.30),
    "grok-4.3": (1.25, 2.50, 0.20),
    "grok-build-0.1": (1.0, 2.0, 0.20),
    "grok-code-fast-1": (1.0, 2.0, 0.20),
    # Mistral (docs.mistral.ai/inference/pricing; list prices)
    "mistral-large-4": (1.36, 4.18, 0.14),
    "mistral-large-2512": (0.50, 1.50, 0.05),
    "mistral-large-latest": (0.50, 1.50, 0.05),
    "mistral-medium-3-5": (1.50, 7.50, 0.15),
    "mistral-medium-latest": (1.50, 7.50, 0.15),
    "mistral-small-2603": (0.15, 0.60, 0.015),
    "mistral-small-latest": (0.15, 0.60, 0.015),
    "codestral-2508": (0.30, 0.90, 0.03),
    "codestral-latest": (0.30, 0.90, 0.03),
    # Groq (console.groq.com/docs/models)
    "gpt-oss-120b": (0.15, 0.60, 0.075),
    "gpt-oss-20b": (0.075, 0.30, 0.0375),
}

DEFAULT_CACHE_FACTOR = {"anthropic": 0.1}   # cached input as a share of input, when not listed
CACHE_WRITE_FACTOR = 1.25                    # Anthropic: writing to the cache


def lookup(model: str, overrides: dict | None = None) -> tuple[float, float, float | None] | None:
    o = (overrides or {}).get(model) or {}
    if "price_in" in o and "price_out" in o:
        cached = o.get("price_cached")
        return float(o["price_in"]), float(o["price_out"]), None if cached is None else float(cached)
    name = model.lower().split("/")[-1]      # openrouter-style "anthropic/claude-sonnet-5-5"
    name = name.split(":")[0]                 # OpenRouter's "some-model:free" and the like
    return PRICES.get(name)


def estimate(model: str, input_tokens: int, output_tokens: int, cached: int = 0,
             cache_write: int = 0, overrides: dict | None = None, family: str = "") -> float:
    """Dollars for one call, or 0.0 when the price isn't known."""
    p = lookup(model, overrides)
    if p is None:
        return 0.0
    price_in, price_out, price_cached = p
    if price_cached is None:
        price_cached = price_in * DEFAULT_CACHE_FACTOR.get(family, 1.0)
    plain = max(input_tokens - cached - cache_write, 0)
    dollars = (plain * price_in + cached * price_cached
               + cache_write * price_in * CACHE_WRITE_FACTOR + output_tokens * price_out)
    return dollars / 1_000_000


def known(model: str, overrides: dict | None = None) -> bool:
    return lookup(model, overrides) is not None
