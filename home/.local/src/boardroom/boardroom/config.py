"""Where Boardroom keeps its files, and reading/writing them.

Two files live in the config directory:
  accounts.toml  the AI accounts you connected (may hold API keys, so it is chmod 600)
  company.toml   the org: who is CEO, debugger, workers, and company-wide settings

A project folder can have its own boardroom.toml, which overrides company.toml for runs there.
"""

from __future__ import annotations

import os
import re
import sys
import tomllib
from pathlib import Path

ACCOUNTS_FILE = "accounts.toml"
COMPANY_FILE = "company.toml"
PROJECT_FILE = "boardroom.toml"

DEFAULT_SETTINGS = {
    "name": "My AI Company",
    "autonomy": "full",        # full | ask | no-shell
    "max_steps": 80,           # tool-use steps per agent before it must stop
    "max_depth": 2,            # how deep subagents may nest under a member
    "max_subagents": 4,        # subagents per spawn call
    "max_tokens": 16000,       # output tokens per model call (API members)
    "token_budget": 0,         # stop the run after this many tokens in total (0 = no limit)
    "sandbox": "auto",         # auto | bwrap | off: how shell commands of API members are confined
}


def config_dir() -> Path:
    if os.environ.get("BOARDROOM_HOME"):
        return Path(os.environ["BOARDROOM_HOME"]).expanduser()
    if sys.platform == "win32" and os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "boardroom"
    base = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(base) / "boardroom"


def load_toml(path: Path) -> dict:
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        return {}


def save_toml(path: Path, data: dict, private: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        if private and sys.platform != "win32":
            os.chmod(tmp, 0o600)
        f.write(dumps(data))
    os.replace(tmp, path)


def load_accounts() -> dict:
    return load_toml(config_dir() / ACCOUNTS_FILE).get("accounts", {})


def save_accounts(accounts: dict) -> None:
    save_toml(config_dir() / ACCOUNTS_FILE, {"accounts": accounts}, private=True)


def load_company(project: Path | None = None) -> dict:
    """The org, with defaults filled in. A project's boardroom.toml wins over the global file."""
    data = load_toml(config_dir() / COMPANY_FILE)
    if project is not None:
        local = load_toml(project / PROJECT_FILE)
        if local:
            data = {**data, **local}
    return {**DEFAULT_SETTINGS, "member": [], "roles": {}, "models": {}, **data}


def save_company(company: dict) -> None:
    save_toml(config_dir() / COMPANY_FILE, company)


# --- minimal TOML writer (tomllib can only read) -------------------------------------------

_BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def _key(k: str) -> str:
    return k if _BARE_KEY.match(k) else _str(k)


def _str(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return _str(v)
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{_key(k)} = {_value(x)}" for k, x in v.items()) + " }"
    raise TypeError(f"can't write {type(v).__name__} to TOML")


def _is_table_array(v) -> bool:
    return isinstance(v, list) and bool(v) and all(isinstance(x, dict) for x in v)


def dumps(data: dict, _prefix: str = "") -> str:
    lines: list[str] = []
    tables, arrays = [], []
    for k, v in data.items():
        if v is None:
            continue
        if isinstance(v, dict):
            tables.append((k, v))
        elif _is_table_array(v):
            arrays.append((k, v))
        else:
            lines.append(f"{_key(k)} = {_value(v)}")
    out = "\n".join(lines) + ("\n" if lines else "")
    for k, v in tables:
        name = f"{_prefix}{_key(k)}"
        scalars = {a: b for a, b in v.items() if not isinstance(b, dict) and not _is_table_array(b)}
        if scalars or not v:
            out += f"\n[{name}]\n"
        out += dumps(v, name + ".")
    for k, items in arrays:
        name = f"{_prefix}{_key(k)}"
        for item in items:
            out += f"\n[[{name}]]\n" + dumps(item, name + ".")
    return out
