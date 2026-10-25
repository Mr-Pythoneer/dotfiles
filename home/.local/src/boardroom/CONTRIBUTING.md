# Contributing

Thanks for helping. A few things to know:

- **No dependencies.** Boardroom uses only the Python standard library (3.11+), and the web UI
  is plain HTML, CSS and JavaScript with no build step. Please keep it that way.
- **Tests run offline.** `python -m unittest discover -s tests -t .` runs a whole company
  against a fake model server (`tests/mock_api.py`) and a fake `claude` program
  (`tests/fake_claude.py`). New features should come with a test that needs no real account.
- **Adding a provider.** If it speaks OpenAI's Chat Completions API, it is usually one line in
  `PRESETS` in `boardroom/connectors/openai_compat.py` (plus a tile in `boardroom/web.py`).
  A CLI agent (like Claude Code or Codex) gets its own connector in `boardroom/connectors/`;
  see `claude_code.py` and `codex.py`.
- **Model tiers and prices** live in `boardroom/catalog.py` and `boardroom/prices.py`. Prices
  must come from the provider's pricing page; say which page and when in your pull request.
- **Events.** Everything a run does is an event (see `boardroom/events.py`); the terminal and the
  web UI only read events. New behaviour should emit events rather than print.
