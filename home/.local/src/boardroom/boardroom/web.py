"""The web UI: `boardroom ui` serves a local website for everything the terminal can do.

The server only listens on 127.0.0.1. API calls need a random token that is put in the URL
the browser opens, and requests must name this server in their Host header (against DNS
rebinding). Static files (the page itself) hold no data and need no token.

API (JSON; the token goes in the X-Boardroom-Token header, or ?t= for the event stream):
  GET  /api/state                 accounts, team, settings, providers, the current run
  GET  /api/models                every model with its tier and score
  GET  /api/events?from=N&t=...   server-sent events of the current run, from event N
  GET  /api/runs?dir=             past runs of a project folder
  GET  /api/run?dir=&name=        one past run: its events and report
  GET  /api/dirs?path=            folders inside a folder (for the folder picker)
  POST /api/mkdir                 {path}
  POST /api/connect               {provider, name?, key?, key_env?, base_url?, models?}
  POST /api/disconnect            {name}
  POST /api/test                  {name}
  POST /api/org/auto              {workers, template, spread}
  POST /api/org/set               {who, model, subagents?}
  POST /api/hire                  {role, model, count?}
  POST /api/fire                  {id}
  POST /api/settings              {name?, autonomy?, max_steps?, ...}
  POST /api/run                   {goal, dir, autonomy?}
  POST /api/reply                 {text}
  POST /api/answer                {allow, always?}
  POST /api/stop                  {}
  POST /api/finish                {}
"""

from __future__ import annotations

import json
import mimetypes
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from boardroom import __version__, catalog, config, connectors, org
from boardroom.connectors import KEY_ENV, PRESETS, ConnectorError

STATIC = Path(__file__).with_name("web")

PROVIDERS = [
    # id, label, what it is, needs a key
    ("claude-code", "Claude", "Your Claude Pro/Max subscription, through Claude Code", False),
    ("codex", "ChatGPT", "Your ChatGPT subscription, through the Codex CLI", False),
    ("gemini-cli", "Gemini (Google account)", "Your Google account or Google AI Pro, through the Gemini CLI", False),
    ("anthropic", "Anthropic API", "Claude models with an API key", True),
    ("openai", "OpenAI API", "GPT models with an API key", True),
    ("deepseek", "DeepSeek", "Strong and very cheap", True),
    ("openrouter", "OpenRouter", "Hundreds of models with one key", True),
    ("gemini", "Google Gemini", "Gemini models with an API key", True),
    ("groq", "Groq", "Very fast open models", True),
    ("mistral", "Mistral", "Mistral models", True),
    ("xai", "xAI", "Grok models", True),
    ("together", "Together", "Open models", True),
    ("ollama", "Ollama", "Free models running on this computer", False),
    ("lmstudio", "LM Studio", "Free models running on this computer", False),
    ("custom", "Other", "Any OpenAI-compatible API", True),
]

AUTONOMY = [
    ("full", "Full autonomy", "Members work without asking, including running commands. "
             "Fastest. Commands are sandboxed where possible."),
    ("ask", "Ask me first", "You approve every command a member wants to run."),
    ("no-shell", "Files only", "Members can only read and write files; no commands at all."),
]


class ApiError(Exception):
    def __init__(self, message: str, code: int = 400):
        super().__init__(message)
        self.code = code


class App:
    def __init__(self, default_dir: Path):
        self.token = secrets.token_urlsafe(18)
        self.default_dir = default_dir.resolve()
        self.lock = threading.Lock()
        self.cond = threading.Condition()
        self.session = None
        self.state = "idle"          # idle | working | waiting (for your reply) | finished
        self.events: list[dict] = []
        self.generation = 0          # goes up with every new run; event streams start over
        self.run_dir: Path | None = None
        self.goal = ""
        self.ask_event = threading.Event()
        self.ask_answer = "n"
        self.asking = False

    # --- events of the current run ----------------------------------------------------------

    def on_event(self, ev: dict) -> None:
        with self.cond:
            self.events.append(ev)
            self.cond.notify_all()

    def web_ask(self, question: str) -> str:
        """Company.approve calls this (after emitting an "ask" event) and waits for the UI."""
        self.ask_event.clear()
        self.asking = True
        try:
            while not self.ask_event.wait(0.5):
                if self.session is None or self.session.stopped:
                    return "n"
            return self.ask_answer
        finally:
            self.asking = False

    # --- state ------------------------------------------------------------------------------

    def snapshot(self) -> dict:
        accounts = config.load_accounts()
        company = config.load_company()
        roles = {**{k: {"description": v} for k, v in org.BUILTIN_ROLES.items()},
                 **(company.get("roles") or {})}
        return {
            "version": __version__,
            "accounts": [_public_account(n, a) for n, a in accounts.items()],
            "company": {k: company[k] for k in config.DEFAULT_SETTINGS},
            "members": company["member"],
            "roles": roles,
            "problems": org.validate(company, accounts) if accounts else [],
            "providers": [{"id": p, "label": label, "about": about, "needs_key": key,
                           "key_env": KEY_ENV.get(p), "connected": False}
                          for p, label, about, key in PROVIDERS],
            "templates": org.TEMPLATES,
            "autonomy": [{"id": i, "label": label, "about": about} for i, label, about in AUTONOMY],
            "default_dir": str(self.default_dir),
            "run": {"state": self.state, "goal": self.goal, "generation": self.generation,
                    "dir": str(self.session.workspace) if self.session else
                           (str(self.run_dir.parent.parent.parent) if self.run_dir else None),
                    "name": self.run_dir.name if self.run_dir else None,
                    "asking": self.asking},
        }

    def models(self) -> list[dict]:
        company = config.load_company()
        cands = org.candidates(config.load_accounts(), company.get("models"))
        cands.sort(key=lambda c: (catalog.TIER_RANK[c.info.tier], -c.info.score))
        return [{"ref": c.ref, "account": c.account, "model": c.model, "tier": c.info.tier,
                 "score": round(c.info.score, 1), "family": c.info.family} for c in cands]

    # --- accounts and team ------------------------------------------------------------------

    def connect(self, b: dict) -> dict:
        from boardroom.cli import Fail, connect
        provider = b.get("provider", "")
        models = b.get("models") or None
        if isinstance(models, list):
            models = ",".join(models)
        try:
            name = connect(provider, b.get("name") or None, b.get("key") or None,
                           b.get("key_env") or None, b.get("base_url") or None, models,
                           interactive=False)
        except (Fail, ConnectorError) as e:
            raise ApiError(str(e)) from None
        company = config.load_company()
        if not company["member"]:
            self._auto(company, 4, "startup", False)
        return {"name": name}

    def _auto(self, company, workers, template, spread):
        from boardroom.cli import _saveable
        try:
            company["member"] = org.auto_members(config.load_accounts(), int(workers), template,
                                                 bool(spread), company.get("models"))
        except (org.OrgError, ValueError) as e:
            raise ApiError(str(e)) from None
        config.save_company(_saveable(company))

    def org_change(self, what: str, b: dict) -> None:
        from boardroom.cli import _saveable
        company = config.load_company()
        accounts = config.load_accounts()
        try:
            if what == "auto":
                return self._auto(company, b.get("workers", 4), b.get("template", "startup"),
                                  b.get("spread", False))
            if what == "set":
                org.set_model(company, b["who"], b["model"], accounts, bool(b.get("subagents")))
            elif what == "hire":
                org.hire(company, b["role"], b["model"], accounts, int(b.get("count") or 1))
            elif what == "fire":
                org.fire(company, b["id"])
        except (org.OrgError, KeyError, ValueError) as e:
            raise ApiError(str(e) if not isinstance(e, KeyError) else f"missing {e}") from None
        config.save_company(_saveable(company))

    def settings(self, b: dict) -> None:
        from boardroom.cli import _saveable
        company = config.load_company()
        for k, v in b.items():
            if k not in config.DEFAULT_SETTINGS:
                raise ApiError(f"unknown setting {k!r}")
            default = config.DEFAULT_SETTINGS[k]
            try:
                v = type(default)(v)
            except (TypeError, ValueError):
                raise ApiError(f"{k} must be a {type(default).__name__}") from None
            if k == "autonomy" and v not in ("full", "ask", "no-shell"):
                raise ApiError("autonomy must be full, ask or no-shell")
            if k == "sandbox" and v not in ("auto", "bwrap", "off"):
                raise ApiError("sandbox must be auto, bwrap or off")
            if k == "name" and not v.strip():
                raise ApiError("the company needs a name")
            company[k] = v
        config.save_company(_saveable(company))

    # --- runs -------------------------------------------------------------------------------

    def start(self, b: dict) -> None:
        from boardroom.session import Session
        goal = (b.get("goal") or "").strip()
        if not goal:
            raise ApiError("Tell the company what to do first.")
        workspace = Path(b.get("dir") or self.default_dir).expanduser()
        if not workspace.is_dir():
            raise ApiError(f"{workspace} is not a folder")
        with self.lock:
            if self.session is not None:
                raise ApiError("The company is already working. Finish or stop that run first.")
            settings = config.load_company(workspace)
            if b.get("autonomy"):
                settings["autonomy"] = b["autonomy"]
            try:
                session = Session(workspace, settings, config.load_accounts(),
                                  subscribers=[self.on_event], ask_user=self.web_ask)
            except (org.OrgError, ConnectorError, RuntimeError) as e:
                raise ApiError(str(e)) from None
            with self.cond:
                self.events = []
                self.generation += 1
                self.cond.notify_all()
            self.session, self.run_dir, self.goal = session, session.run_dir, goal
            self.state = "working"
            session.start(goal)
        self._send_in_background(goal)

    def reply(self, b: dict) -> None:
        text = (b.get("text") or "").strip()
        if not text:
            raise ApiError("Write something to the CEO first.")
        with self.lock:
            if self.session is None or self.state != "waiting":
                raise ApiError("The CEO isn't waiting for a reply right now.")
            self.state = "working"
        self._send_in_background(text)

    def _send_in_background(self, text: str) -> None:
        session = self.session

        def work():
            try:
                session.send(text)
            finally:
                with self.lock:
                    self.state = "waiting"
                if session.stopped:
                    self.finish()

        threading.Thread(target=work, daemon=True).start()

    def answer(self, b: dict) -> None:
        if not self.asking:
            raise ApiError("Nobody is waiting for an answer.")
        self.ask_answer = "a" if b.get("always") else ("y" if b.get("allow") else "n")
        self.ask_event.set()

    def stop(self) -> None:
        if self.session is not None:
            self.session.stop()
            self.ask_event.set()   # a pending question counts as "no"

    def finish(self) -> None:
        with self.lock:
            session, self.session = self.session, None
            if session is None:
                return
            self.state = "finished"
        session.finish()

    # --- history and folders ----------------------------------------------------------------

    def runs(self, folder: str) -> list[dict]:
        from boardroom.session import list_runs
        return list_runs(Path(folder or self.default_dir).expanduser())

    def run_detail(self, folder: str, name: str) -> dict:
        d = Path(folder or self.default_dir).expanduser() / ".boardroom" / "runs" / name
        if "/" in name or "\\" in name or name.startswith(".") or not d.is_dir():
            raise ApiError("no such run", 404)
        events = []
        try:
            with open(d / "events.jsonl", encoding="utf-8") as f:
                events = [json.loads(line) for line in f if line.strip()]
        except (OSError, ValueError):
            pass
        report = d / "report.md"
        return {"events": events,
                "report": report.read_text(encoding="utf-8") if report.exists() else None}

    def dirs(self, path: str) -> dict:
        p = Path(path or self.default_dir).expanduser().resolve()
        if not p.is_dir():
            raise ApiError(f"{p} is not a folder")
        try:
            names = sorted((c.name for c in p.iterdir() if c.is_dir() and not c.name.startswith(".")),
                           key=str.lower)
        except PermissionError:
            names = []
        return {"path": str(p), "parent": str(p.parent) if p.parent != p else None,
                "home": str(Path.home()), "dirs": names[:500],
                "has_runs": (p / ".boardroom" / "runs").is_dir()}

    def mkdir(self, b: dict) -> dict:
        p = Path(b.get("path") or "").expanduser()
        if not p.is_absolute():
            raise ApiError("give a full path")
        p.mkdir(parents=True, exist_ok=True)
        return {"path": str(p.resolve())}

    def shutdown(self) -> None:
        if self.session is not None:
            self.session.stop()
            self.ask_event.set()
            self.finish()


def _public_account(name: str, a: dict) -> dict:
    """An account without its key."""
    return {"name": name, "kind": a.get("kind"), "preset": a.get("preset"),
            "base_url": a.get("base_url") or (PRESETS.get(a.get("preset") or "", ("",))[0] or None),
            "models": a.get("models", []), "key_env": a.get("key_env"),
            "has_key": bool(a.get("key")) or bool(a.get("key_env") and os.environ.get(a["key_env"]))}


def make_handler(app: App, port_box: dict):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        # --- plumbing -----------------------------------------------------------------------

        def _host_ok(self) -> bool:
            host = (self.headers.get("host") or "").lower()
            port = port_box["port"]
            return host in (f"127.0.0.1:{port}", f"localhost:{port}")

        def _authed(self, query: dict) -> bool:
            token = self.headers.get("x-boardroom-token") or (query.get("t") or [""])[0]
            return secrets.compare_digest(token, app.token)

        def _json(self, obj, code=200):
            data = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-length", str(len(data)))
            self.send_header("cache-control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _body(self) -> dict:
            n = int(self.headers.get("content-length") or 0)
            if n > 2_000_000:
                raise ApiError("request too large", 413)
            try:
                b = json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                raise ApiError("bad JSON") from None
            if not isinstance(b, dict):
                raise ApiError("bad JSON")
            return b

        def _static(self, path: str):
            name = "index.html" if path in ("", "/") else path.lstrip("/")
            f = (STATIC / name).resolve()
            if STATIC.resolve() not in f.parents or not f.is_file():
                return self._json({"error": "not found"}, 404)
            data = f.read_bytes()
            ctype = mimetypes.guess_type(f.name)[0] or "application/octet-stream"
            if ctype.startswith("text/") or ctype.endswith("javascript"):
                ctype += "; charset=utf-8"
            self.send_response(200)
            self.send_header("content-type", ctype)
            self.send_header("content-length", str(len(data)))
            self.send_header("cache-control", "no-cache")
            self.send_header("x-content-type-options", "nosniff")
            self.send_header("referrer-policy", "no-referrer")
            self.send_header("content-security-policy",
                             "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:")
            self.end_headers()
            self.wfile.write(data)

        def _route(self, method: str):
            if not self._host_ok():
                return self._json({"error": "wrong host"}, 403)
            url = urlparse(self.path)
            q = parse_qs(url.query)
            if not url.path.startswith("/api/"):
                if method != "GET":
                    return self._json({"error": "not found"}, 404)
                return self._static(url.path)
            if not self._authed(q):
                return self._json({"error": "This page's link has expired. Open the link that "
                                            "`boardroom ui` printed."}, 401)
            arg = lambda k: (q.get(k) or [""])[0]   # noqa: E731
            try:
                if method == "GET":
                    if url.path == "/api/events":
                        return self._events(int(arg("from") or 0), int(arg("gen") or 0))
                    out = {
                        "/api/state": lambda: app.snapshot(),
                        "/api/models": lambda: app.models(),
                        "/api/runs": lambda: app.runs(arg("dir")),
                        "/api/run": lambda: app.run_detail(arg("dir"), arg("name")),
                        "/api/dirs": lambda: app.dirs(arg("path")),
                    }.get(url.path)
                    if out is None:
                        return self._json({"error": "not found"}, 404)
                    return self._json(out())
                b = self._body()
                actions = {
                    "/api/connect": lambda: app.connect(b),
                    "/api/disconnect": lambda: _disconnect(b),
                    "/api/test": lambda: _test(b),
                    "/api/org/auto": lambda: app.org_change("auto", b),
                    "/api/org/set": lambda: app.org_change("set", b),
                    "/api/hire": lambda: app.org_change("hire", b),
                    "/api/fire": lambda: app.org_change("fire", b),
                    "/api/settings": lambda: app.settings(b),
                    "/api/run": lambda: app.start(b),
                    "/api/reply": lambda: app.reply(b),
                    "/api/answer": lambda: app.answer(b),
                    "/api/stop": lambda: app.stop(),
                    "/api/finish": lambda: app.finish(),
                    "/api/mkdir": lambda: app.mkdir(b),
                }
                fn = actions.get(url.path)
                if fn is None:
                    return self._json({"error": "not found"}, 404)
                return self._json(fn() or {"ok": True})
            except ApiError as e:
                return self._json({"error": str(e)}, e.code)
            except OSError as e:
                return self._json({"error": str(e)}, 400)

        def _events(self, start: int, gen: int):
            """Server-sent events: every event of the current run from `start` on."""
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.send_header("cache-control", "no-store")
            self.send_header("connection", "close")
            self.end_headers()
            self.close_connection = True
            i = start if gen == app.generation else 0
            my_gen = app.generation
            if gen != my_gen:
                self._sse("reset", {"generation": my_gen})
            try:
                while True:
                    with app.cond:
                        if app.generation == my_gen and len(app.events) <= i:
                            app.cond.wait(15)
                        if app.generation != my_gen:
                            my_gen, i = app.generation, 0
                            new, reset = [], True
                        else:
                            new, reset = app.events[i:], False
                    if reset:
                        self._sse("reset", {"generation": my_gen})
                        continue
                    if not new:
                        self.wfile.write(b": still here\n\n")
                        self.wfile.flush()
                        continue
                    for ev in new:
                        self._sse("event", ev, i)
                        i += 1
            except (BrokenPipeError, ConnectionResetError, OSError):
                return

        def _sse(self, kind: str, data, ident=None):
            msg = f"event: {kind}\n"
            if ident is not None:
                msg += f"id: {ident}\n"
            msg += f"data: {json.dumps(data, ensure_ascii=False)}\n\n"
            self.wfile.write(msg.encode())
            self.wfile.flush()

        def do_GET(self):
            self._route("GET")

        def do_POST(self):
            self._route("POST")

    return Handler


def _disconnect(b: dict) -> None:
    accounts = config.load_accounts()
    if b.get("name") not in accounts:
        raise ApiError("no such account")
    del accounts[b["name"]]
    config.save_accounts(accounts)


def _test(b: dict) -> dict:
    accounts = config.load_accounts()
    if b.get("name") not in accounts:
        raise ApiError("no such account")
    try:
        ok, msg = connectors.make(b["name"], accounts[b["name"]]).test()
    except ConnectorError as e:
        ok, msg = False, str(e)
    return {"ok": ok, "message": msg}


def serve(folder: Path, port: int = 0, open_browser: bool = True) -> None:
    app = App(folder)
    port_box = {"port": port}
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(app, port_box))
    server.daemon_threads = True
    port_box["port"] = server.server_address[1]
    url = f"http://127.0.0.1:{port_box['port']}/#t={app.token}"
    print(f"Boardroom is open at:\n  {url}\n(keep this window open; press Ctrl-C to close Boardroom)",
          flush=True)
    if open_browser:
        import webbrowser
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("\nClosing Boardroom…", flush=True)
    finally:
        app.shutdown()
        server.server_close()
        time.sleep(0.1)
