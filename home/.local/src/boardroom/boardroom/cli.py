"""The `boardroom` command."""

from __future__ import annotations

import argparse
import getpass
import os
import sys
import threading
from pathlib import Path

from boardroom import __version__, catalog, config, connectors, org
from boardroom.connectors import KEY_ENV, PRESETS, PROVIDERS, ConnectorError
from boardroom.render_term import Style, TermRenderer, display_name, use_color

st = Style(use_color(sys.stdout))
AUTONOMY = {
    "full": "members run shell commands without asking (API members inside a sandbox when "
            "bubblewrap is installed)",
    "ask": "you approve every shell command",
    "no-shell": "members can only read and write files",
}


class Fail(Exception):
    pass


def say(msg: str = "") -> None:
    print(msg, flush=True)


def ask(question: str, default: str = "") -> str:
    try:
        answer = input(question).strip()
    except EOFError:
        return default
    return answer or default


def yes(question: str, default: bool = True) -> bool:
    hint = "[Y/n]" if default else "[y/N]"
    return ask(f"{question} {hint} ", "y" if default else "n").lower().startswith("y")


# --- accounts ------------------------------------------------------------------------------

def connect(provider: str, name: str | None = None, key: str | None = None,
            key_env: str | None = None, base_url: str | None = None, models: str | None = None,
            command: str | None = None, interactive: bool = True) -> str:
    provider = provider.lower()
    if provider not in PROVIDERS:
        raise Fail(f"Unknown provider {provider!r}. Choose one of: {', '.join(sorted(PROVIDERS))}")
    kind, default_name = PROVIDERS[provider]
    accounts = config.load_accounts()
    name = name or default_name
    cfg: dict = {"kind": kind}
    if kind == "openai-compat":
        cfg["preset"] = provider
        if provider == "custom":
            if not base_url:
                raise Fail("A custom provider needs --base-url (an OpenAI-compatible API, ending in /v1)")
        if base_url:
            cfg["base_url"] = base_url
    elif base_url:
        cfg["base_url"] = base_url
    if command:
        cfg["command"] = command

    if kind in ("anthropic", "openai-compat") and provider not in ("ollama", "lmstudio"):
        env = key_env or KEY_ENV.get(provider)
        if key:
            cfg["key"] = key
        elif env and os.environ.get(env):
            cfg["key_env"] = env
            say(st.dim(f"  using the key in ${env} (only the variable name is saved)"))
        elif interactive and sys.stdin.isatty():
            k = getpass.getpass(f"  API key for {provider} (input hidden): ").strip()
            if not k:
                raise Fail("No key given")
            cfg["key"] = k
        else:
            raise Fail(f"No API key. Pass --key, or set ${env or 'YOUR_KEY_VARIABLE'} and pass --key-env")

    conn = connectors.make(name, cfg)
    if models:
        cfg["models"] = [m.strip() for m in models.split(",") if m.strip()]
    else:
        try:
            cfg["models"] = conn.list_models()
        except ConnectorError as e:
            if conn.is_cli:
                raise Fail(str(e))
            fallback = PRESETS.get(provider, (None, None, []))[2]
            if not fallback:
                raise Fail(f"Couldn't list the models: {e}\n"
                           "Check the key, or name the models yourself with --models a,b")
            say(st.dim(f"  couldn't list models ({e}); using {', '.join(fallback)}"))
            cfg["models"] = fallback
    if not cfg["models"]:
        raise Fail("This account has no usable models. Name them with --models a,b")
    if conn.is_cli:
        ok, msg = conn.test()
        if not ok:
            raise Fail(f"{name}: {msg}")
        say(st.dim(f"  {msg}"))

    replaced = name in accounts
    accounts[name] = cfg
    config.save_accounts(accounts)
    best = sorted(cfg["models"], key=lambda m: -catalog.classify(m).score)[:4]
    say(f"{st.green('✓')} {'Updated' if replaced else 'Connected'} {st.bold(name)} "
        f"({kind}, {len(cfg['models'])} models, best: {', '.join(best)})")
    return name


def cmd_connect(a) -> None:
    connect(a.provider, a.name, a.key, a.key_env, a.base_url, a.models, a.command)
    company = config.load_company()
    if not company["member"]:
        say("\nYour company has nobody in it yet, so here is an automatic team:")
        build_org(company, 4, "startup", False)
    else:
        say(st.dim("Run `boardroom org auto` to rebuild the team with this account included."))


def cmd_disconnect(a) -> None:
    accounts = config.load_accounts()
    if a.name not in accounts:
        raise Fail(f"No account called {a.name!r}")
    del accounts[a.name]
    config.save_accounts(accounts)
    say(f"Removed {a.name}.")
    for p in org.validate(config.load_company(), accounts):
        say(st.c(220, "! " + p))


def cmd_accounts(a) -> None:
    accounts = config.load_accounts()
    if not accounts:
        say("No accounts yet. Run `boardroom setup`, or e.g. `boardroom connect claude-code`.")
        return
    for name, cfg in accounts.items():
        line = f"{st.bold(name):<20} {cfg.get('kind', '?'):<14} {len(cfg.get('models', [])):>3} models"
        if not a.no_test:
            try:
                ok, msg = connectors.make(name, cfg).test()
            except ConnectorError as e:
                ok, msg = False, str(e)
            line += "  " + (st.green("✓ " + msg) if ok else st.red("✗ " + msg))
        say(line)


def cmd_models(a) -> None:
    accounts = config.load_accounts()
    if a.refresh:
        for name, cfg in accounts.items():
            try:
                cfg["models"] = connectors.make(name, cfg).list_models()
                say(st.dim(f"{name}: {len(cfg['models'])} models"))
            except ConnectorError as e:
                say(st.red(f"{name}: {e}"))
        config.save_accounts(accounts)
    cands = org.candidates(accounts, config.load_company().get("models"))
    if not cands:
        say("No models yet. Connect an account first: boardroom setup")
        return
    for tier in catalog.TIERS:
        group = sorted((c for c in cands if c.info.tier == tier), key=lambda c: -c.info.score)
        if not group:
            continue
        say(st.bold(f"\n{tier}"))
        for c in group[: a.limit]:
            say(f"  {c.ref:<45} {c.info.score:5.1f}  {st.dim(c.info.family)}")
        if len(group) > a.limit:
            say(st.dim(f"  ... and {len(group) - a.limit} more (use --limit)"))


# --- the org -------------------------------------------------------------------------------

def show_org(company: dict) -> None:
    members = company["member"]
    say(st.bold(company["name"]) + st.dim(f"  ·  autonomy: {company['autonomy']}"))
    if not members:
        say("  (nobody yet; run `boardroom org auto`)")
        return
    ceo = next((m for m in members if m["role"] == "ceo"), None)
    rest = [m for m in members if m is not ceo]
    r = TermRenderer(color=st.on)

    width = max(len(display_name(m["id"])) for m in members) + 2

    def label(m, indent=0):
        account, model = m["model"].split(":", 1)
        s = r.st.c(r.color_of(m["id"]), f"{display_name(m['id']):<{width + indent}}", bold=True)
        s += f" {model} {st.dim('· ' + account)}"
        if m["role"] not in ("ceo", "debugger", "worker"):
            s += st.dim(f"  [{m['role']}]")
        if m.get("subagent_model"):
            s += st.dim(f"   subagents: {m['subagent_model'].split(':', 1)[1]}")
        return s

    if ceo:
        say(label(ceo, indent=3))
    for i, m in enumerate(rest):
        say(("└─ " if i == len(rest) - 1 else "├─ ") + label(m))


def build_org(company, workers, template, spread) -> None:
    accounts = config.load_accounts()
    try:
        company["member"] = org.auto_members(accounts, workers, template, spread,
                                             company.get("models"))
    except org.OrgError as e:
        raise Fail(str(e))
    config.save_company(_saveable(company))
    say()
    show_org(company)


def _saveable(company: dict) -> dict:
    """Leave defaults out of company.toml so that future default changes reach the user."""
    out = {k: v for k, v in company.items()
           if not (k in config.DEFAULT_SETTINGS and config.DEFAULT_SETTINGS[k] == v)}
    out.pop("name", None)
    out = {"name": company["name"], **out}
    for k in ("roles", "models"):
        if not out.get(k):
            out.pop(k, None)
    return out


def cmd_org(a) -> None:
    company = config.load_company()
    if a.action == "auto":
        build_org(company, a.workers, a.template, a.spread)
        say(st.dim("\nChange it with `boardroom org set`, `boardroom hire`, `boardroom fire`."))
    elif a.action == "set":
        if len(a.args) != 2:
            raise Fail("Usage: boardroom org set <member|role> <account:model> [--subagents]")
        try:
            changed = org.set_model(company, a.args[0], a.args[1], config.load_accounts(), a.subagents)
        except org.OrgError as e:
            raise Fail(str(e))
        config.save_company(_saveable(company))
        say(f"{st.green('✓')} updated {', '.join(changed)}\n")
        show_org(company)
    else:
        show_org(company)


def cmd_hire(a) -> None:
    company = config.load_company()
    try:
        added = org.hire(company, a.role, a.model, config.load_accounts(), a.count, a.id)
    except org.OrgError as e:
        raise Fail(str(e))
    config.save_company(_saveable(company))
    say(f"{st.green('✓')} hired {', '.join(added)}\n")
    show_org(company)


def cmd_fire(a) -> None:
    company = config.load_company()
    try:
        for mid in a.ids:
            org.fire(company, mid)
    except org.OrgError as e:
        raise Fail(str(e))
    config.save_company(_saveable(company))
    say(f"{st.green('✓')} fired {', '.join(a.ids)}\n")
    show_org(company)


def cmd_config(a) -> None:
    company = config.load_company()
    if not a.key:
        for k in config.DEFAULT_SETTINGS:
            say(f"{k:<14} {company[k]!r}")
        return
    if a.key not in config.DEFAULT_SETTINGS:
        raise Fail(f"Unknown setting {a.key!r}. Settings: {', '.join(config.DEFAULT_SETTINGS)}")
    if a.value is None:
        say(repr(company[a.key]))
        return
    default = config.DEFAULT_SETTINGS[a.key]
    try:
        value = type(default)(a.value)
    except ValueError:
        raise Fail(f"{a.key} must be a {type(default).__name__}")
    if a.key == "autonomy" and value not in AUTONOMY:
        raise Fail(f"autonomy must be one of: {', '.join(AUTONOMY)}")
    if a.key == "sandbox" and value not in ("auto", "bwrap", "off"):
        raise Fail("sandbox must be auto, bwrap or off")
    company[a.key] = value
    config.save_company(_saveable(company))
    say(f"{st.green('✓')} {a.key} = {value!r}")


# --- running -------------------------------------------------------------------------------

def cmd_run(a) -> None:
    from boardroom.session import Session

    workspace = Path(a.dir or ".").expanduser().resolve()
    if not workspace.is_dir():
        raise Fail(f"{workspace} is not a folder")
    settings = config.load_company(workspace)
    if a.autonomy:
        settings["autonomy"] = a.autonomy
    if a.budget is not None:
        settings["token_budget"] = a.budget
    accounts = config.load_accounts()
    problems = org.validate(settings, accounts)
    if problems:
        raise Fail("\n".join(problems))

    goal = " ".join(a.goal).strip()
    interactive = sys.stdin.isatty()
    if not goal:
        if not interactive:
            raise Fail('Say what the company should do: boardroom run "build a todo app"')
        say(st.bold(f"{settings['name']}") + st.dim(f" · {workspace}"))
        goal = ask("What should the company do?\n> ")
        if not goal:
            return

    renderer = TermRenderer(verbose=a.verbose)
    try:
        session = Session(workspace, settings, accounts, subscribers=[renderer],
                          ask_user=ask if interactive else None)
    except (org.OrgError, ConnectorError, RuntimeError) as e:
        raise Fail(str(e))
    session.start(goal)
    try:
        while True:
            res = _run_interruptible(session, goal)
            _print_report(res.text)
            if not interactive or a.no_chat or session.stopped:
                break
            goal = ask(st.dim("\nReply to the CEO, or press Enter to finish:\n> "))
            if not goal:
                break
    finally:
        session.finish()
    if session.stopped and threading.active_count() > 1:
        # A member may still sit in a question nobody will answer; don't wait for it.
        sys.stdout.flush()
        os._exit(130)


def _run_interruptible(session, goal):
    box = {}
    t = threading.Thread(target=lambda: box.setdefault("res", session.send(goal)), daemon=True)
    t.start()
    try:
        while t.is_alive():
            t.join(0.3)
    except KeyboardInterrupt:
        say(st.c(220, "\nStopping every member… (press Ctrl-C again to quit at once)"))
        session.stop()
        try:
            t.join(30)
        except KeyboardInterrupt:
            os._exit(130)
    from boardroom.connectors.base import RunResult
    return box.get("res") or RunResult("(stopped)", ok=False)


def _print_report(text: str) -> None:
    say("\n" + st.bold("──── CEO's report ────"))
    say(text.strip() or "(empty)")


def cmd_runs(a) -> None:
    from boardroom.session import list_runs
    runs = list_runs(Path(a.dir or ".").resolve())
    if not runs:
        say("No runs in this folder yet.")
        return
    for r in runs[: a.limit]:
        ok = r["ok"]
        mark = st.green("✓") if ok else (st.red("✗") if ok is False else st.dim("…"))
        say(f"{mark} {st.bold(r['name'])}  {r['goal'][:90]}")


def cmd_show(a) -> None:
    runs_dir = Path(a.dir or ".").resolve() / ".boardroom" / "runs"
    from boardroom.session import list_runs
    names = [r["name"] for r in list_runs(runs_dir.parent.parent)]
    pick = [n for n in names if n == a.run] if a.run else names[:1]
    if not pick:
        raise Fail("No such run. See: boardroom runs")
    report = runs_dir / pick[0] / "report.md"
    say(report.read_text(encoding="utf-8") if report.exists() else "That run has no report.")


# --- setup wizard --------------------------------------------------------------------------

API_CHOICES = [("deepseek", "DeepSeek"), ("openai", "OpenAI API"), ("anthropic", "Anthropic API"),
               ("openrouter", "OpenRouter (hundreds of models, one key)"), ("gemini", "Google Gemini"),
               ("groq", "Groq"), ("mistral", "Mistral"), ("xai", "xAI Grok"), ("together", "Together"),
               ("ollama", "Ollama (models on this computer, free)")]


def cmd_setup(a) -> None:
    import shutil
    if not sys.stdin.isatty():
        raise Fail("setup is interactive; run it in a terminal")
    say(st.bold("Welcome to Boardroom.") + "\nLet's connect the AI accounts you have. Boardroom "
        "turns them into a company: the strongest model becomes the CEO, a model from another "
        "company becomes the debugger, and good-value models become workers.\n")
    accounts = config.load_accounts()
    if accounts:
        say(f"Already connected: {', '.join(accounts)}\n")

    def try_connect(*args, **kw):
        try:
            connect(*args, **kw)
        except (Fail, ConnectorError) as e:
            say(st.red(f"  ✗ {e}"))

    if shutil.which("claude") and "claude" not in accounts:
        if yes("Claude Code is installed. Use your Claude account through it?"):
            try_connect("claude-code")
    if shutil.which("codex") and "chatgpt" not in accounts:
        if yes("The Codex CLI is installed. Use your ChatGPT account through it?"):
            try_connect("codex")
    if shutil.which("gemini") and "google" not in accounts:
        if yes("The Gemini CLI is installed. Use your Google account through it?"):
            try_connect("gemini-cli")
    for provider, env in KEY_ENV.items():
        if os.environ.get(env) and provider not in config.load_accounts():
            if yes(f"Found ${env}. Connect {provider}?"):
                try_connect(provider, key_env=env)
    while True:
        say("\nAdd an API key for another provider? (Enter to skip)")
        for i, (_, label) in enumerate(API_CHOICES, 1):
            say(f"  {i:>2}. {label}")
        pick = ask("> ")
        if not pick:
            break
        if not pick.isdigit() or not 1 <= int(pick) <= len(API_CHOICES):
            say("Type a number from the list.")
            continue
        try_connect(API_CHOICES[int(pick) - 1][0])

    accounts = config.load_accounts()
    if not accounts:
        say("\nNo accounts connected. Install Claude Code or Codex, or get an API key, and run "
            "`boardroom setup` again.")
        return
    company = config.load_company()
    name = ask(f"\nName your company [{company['name']}]: ", company["name"])
    company["name"] = name
    workers = ask("How many workers? [4]: ", "4")
    say("\nHow much may members do without asking you?")
    for i, (k, v) in enumerate(AUTONOMY.items(), 1):
        say(f"  {i}. {k:<9} {st.dim(v)}")
    choice = ask("> [1]: ", "1")
    company["autonomy"] = list(AUTONOMY)[int(choice) - 1] if choice in ("1", "2", "3") else "full"
    build_org(company, int(workers) if workers.isdigit() else 4, "startup", False)
    say(f"\n{st.green('All set.')} Go to a project folder and try:\n"
        f'  boardroom run "make a small website about penguins, with tests"\n'
        f"or open the visual version with: boardroom ui\n")


def cmd_ui(a) -> None:
    from boardroom.web import serve
    folder = Path(a.dir or ".").expanduser().resolve()
    if not folder.is_dir():
        raise Fail(f"{folder} is not a folder")
    serve(folder, port=a.port, open_browser=not a.no_open)


# --- argument parsing ----------------------------------------------------------------------

def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="boardroom",
        description="Run a company of AI agents: a CEO, a debugger and workers, made from the "
                    "AI accounts you connect.")
    p.add_argument("--version", action="version", version=f"boardroom {__version__}")
    sub = p.add_subparsers(dest="cmd", metavar="<command>")

    s = sub.add_parser("setup", help="guided setup: connect accounts and build the company")
    s.set_defaults(fn=cmd_setup)

    s = sub.add_parser("ui", help="open Boardroom in your web browser")
    s.add_argument("-C", "--dir", help="project folder to start in (default: here)")
    s.add_argument("--port", type=int, default=0, help="port to use (default: any free one)")
    s.add_argument("--no-open", action="store_true", help="don't open the browser; just print the link")
    s.set_defaults(fn=cmd_ui)

    s = sub.add_parser("connect", help="connect an AI account",
                       description="Providers: " + ", ".join(sorted(PROVIDERS)))
    s.add_argument("provider")
    s.add_argument("--name", help="what to call this account (default: the provider's name)")
    s.add_argument("--key", help="API key (stored in the config file)")
    s.add_argument("--key-env", help="name of an environment variable holding the key (only the name is stored)")
    s.add_argument("--base-url", help="API base URL (for custom or self-hosted)")
    s.add_argument("--models", help="comma-separated models, instead of asking the API")
    s.add_argument("--command", help="path of the CLI program (claude-code, codex)")
    s.set_defaults(fn=cmd_connect)

    s = sub.add_parser("disconnect", help="remove an account")
    s.add_argument("name")
    s.set_defaults(fn=cmd_disconnect)

    s = sub.add_parser("accounts", help="list accounts and test them")
    s.add_argument("--no-test", action="store_true")
    s.set_defaults(fn=cmd_accounts)

    s = sub.add_parser("models", help="list models with their tier and score")
    s.add_argument("--refresh", action="store_true", help="ask every account for its models again")
    s.add_argument("--limit", type=int, default=15)
    s.set_defaults(fn=cmd_models)

    s = sub.add_parser("org", help="show the org chart, or build/change it",
                       description="boardroom org | boardroom org auto [--workers N] | "
                                   "boardroom org set <member|role> <account:model>")
    s.add_argument("action", nargs="?", choices=["show", "auto", "set"], default="show")
    s.add_argument("args", nargs="*")
    s.add_argument("--workers", type=int, default=4)
    s.add_argument("--template", default="startup", choices=list(org.TEMPLATES))
    s.add_argument("--spread", action="store_true", help="spread workers over all accounts")
    s.add_argument("--subagents", action="store_true", help="with set: change the subagent model")
    s.set_defaults(fn=cmd_org)

    s = sub.add_parser("hire", help="add a member: boardroom hire worker deepseek:deepseek-v4-pro")
    s.add_argument("role")
    s.add_argument("model", help="account:model")
    s.add_argument("--count", type=int, default=1)
    s.add_argument("--id")
    s.set_defaults(fn=cmd_hire)

    s = sub.add_parser("fire", help="remove members: boardroom fire worker-3")
    s.add_argument("ids", nargs="+")
    s.set_defaults(fn=cmd_fire)

    s = sub.add_parser("config", help="show or change a company setting")
    s.add_argument("key", nargs="?")
    s.add_argument("value", nargs="?")
    s.set_defaults(fn=cmd_config)

    s = sub.add_parser("run", help="give the company a goal and watch it work")
    s.add_argument("goal", nargs="*")
    s.add_argument("-C", "--dir", help="project folder (default: here)")
    s.add_argument("--autonomy", choices=list(AUTONOMY))
    s.add_argument("--budget", type=int, help="stop after this many tokens in total")
    s.add_argument("--no-chat", action="store_true", help="don't offer to continue after the report")
    s.add_argument("-v", "--verbose", action="store_true")
    s.set_defaults(fn=cmd_run)

    s = sub.add_parser("runs", help="list past runs in this folder")
    s.add_argument("-C", "--dir")
    s.add_argument("--limit", type=int, default=20)
    s.set_defaults(fn=cmd_runs)

    s = sub.add_parser("show", help="print the report of the last (or a given) run")
    s.add_argument("run", nargs="?")
    s.add_argument("-C", "--dir")
    s.set_defaults(fn=cmd_show)
    return p


def main(argv=None) -> None:
    p = parser()
    a = p.parse_args(argv)
    if not getattr(a, "fn", None):
        p.print_help()
        if not config.load_accounts():
            say("\nNew here? Run `boardroom ui` to set everything up in your browser,\n"
                "or `boardroom setup` to do it here in the terminal.")
        return
    try:
        a.fn(a)
    except Fail as e:
        say(st.red(str(e)))
        sys.exit(1)
    except KeyboardInterrupt:
        say("")
        sys.exit(130)
