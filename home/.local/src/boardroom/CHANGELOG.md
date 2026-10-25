# Changelog

## 0.1.0 (unreleased)

First version.

- Connect AI accounts: Claude Code, Codex and Gemini CLI (subscriptions, through the official CLIs), the
  Anthropic API, and any OpenAI-compatible API (OpenAI, DeepSeek, OpenRouter, Gemini, Groq,
  Mistral, xAI, Together, Ollama, LM Studio, or a custom URL).
- Automatic org: the strongest model becomes CEO, a strong model from another maker the
  debugger, good-value models the workers, fast models their subagents. Change it by hand with
  `org set`, `hire` and `fire`, or in `company.toml`. Custom roles.
- The CEO delegates in parallel; members spawn subagents. CLI members get the company tools
  through a local MCP server.
- Autonomy levels (full, ask, no-shell), with a bubblewrap sandbox for API members' commands.
- Terminal view (`boardroom run`) and web UI (`boardroom ui`): live org chart, activity feed,
  approvals, the CEO's report and replies, team and account management, history.
- Run logs (`events.jsonl`) and reports; token counts and estimated API cost.
