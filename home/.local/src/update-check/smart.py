"""The adaptive half of update-check: a history of your files, why things broke, and Claude for the
problems no built-in fix covers. update-check imports it; nothing here runs on its own.

History: a private git repo (~/.local/state/update-check/history.git, its work tree is your home; it is
never pushed anywhere) holding every small text file under ~/.config, ~/.local/bin,
~/.local/share/applications and ~/.local/share/arch-kit. The list is found fresh every time, so new
apps and configs are covered without being added anywhere. Left out: app profiles (folders with
browser-style caches: Chrome, Discord, Bitwarden...), folders over 20 MB, files over 256 KB, binary
files and anything named like a secret (tokens, passwords, keys). A snapshot is taken before every
update and every fix run; the tag "good" marks the last check that found nothing wrong.

Claude: problems left over after the built-in fixes go to `claude -p` with what changed since the last
good check. It may edit files only in those same folders (so every change can be undone), run a list
of read-only and restart commands, and never sudo, delete, install or remove anything: whatever needs
root comes back as a command for you to run. It answers in a fixed JSON form, which becomes the report.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".local/state/update-check"
GIT_DIR = STATE / "history.git"
RUNS = STATE / "runs"            # one JSON report per Claude fix run
LESSONS = STATE / "lessons.md"   # what earlier runs learned about this system; goes into every prompt
ATTEMPTS = STATE / "ai-attempts.json"
UNDONE = STATE / "undone"        # files a fix run created, moved here when it's undone (never deleted)
ROOTS = (".config", ".local/bin", ".local/share/applications", ".local/share/arch-kit")
MAX_FILE = 256 * 1024
MAX_DIR = 20 * 1024 * 1024
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".cache", "Cache", "cache", "logs", "Crashpad"}
# Chromium/Electron profiles (Chrome, Discord, Bitwarden, VS Code) and Mozilla ones (Firefox, Zen, Thunderbird)
PROFILE_MARKERS = {"Local Storage", "IndexedDB", "Cookies", "Session Storage", "GPUCache", "blob_storage",
                   "Service Worker", "CacheStorage", "Code Cache",
                   "prefs.js", "times.json", "compatibility.ini", "places.sqlite", "logins.json", "key4.db", "cert9.db"}
SECRET = re.compile(r"token|secret|passw|credential|cookie|keyring|private|auth|\.key$|\.pem$|\.kdbx$|"
                    r"^hosts\.yml$|^\.?netrc$", re.I)
# updates that commonly break desktop pieces; named as the likely cause when nothing more specific is
KEY_PACKAGES = re.compile(r"^(qt6-|hyprland|quickshell|caelestia|python$|python-|glibc|mesa|linux$|systemd$|"
                          r"pipewire|wireplumber|gtk[34]|icu|boost|openssl|libxml2|wayland|kitty|xdg-desktop-portal)")
NO_AI = "UPDATE_CHECK_NO_AI"     # set for anything Claude runs, so a nested update-check never calls Claude


# ---- history ---------------------------------------------------------------------------------------

def git(*args, data=None):
    """git on the history repo -> (exit code, stdout text). Your own git config (hooks, signing) isn't used."""
    env = dict(os.environ, GIT_DIR=str(GIT_DIR), GIT_WORK_TREE=str(HOME), GIT_TERMINAL_PROMPT="0",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    try:
        p = subprocess.run(["git", "-c", "core.quotepath=off", *args], input=data, capture_output=True,
                           env=env, cwd=HOME, timeout=300)
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""
    return p.returncode, p.stdout.decode(errors="replace")


def ensure_repo():
    if (GIT_DIR / "HEAD").exists():
        return True
    if not shutil.which("git"):
        return False
    STATE.mkdir(parents=True, exist_ok=True)
    if subprocess.run(["git", "init", "-q", "--bare", str(GIT_DIR)], capture_output=True).returncode != 0:
        return False
    os.chmod(GIT_DIR, 0o700)
    for k, v in (("core.bare", "false"), ("core.worktree", str(HOME)), ("status.showUntrackedFiles", "no"),
                 ("user.name", "update-check"), ("user.email", "update-check@localhost"),
                 ("commit.gpgsign", "false"), ("tag.gpgsign", "false"), ("gc.auto", "256")):
        git("config", k, v)
    return True


def _is_text(path):
    try:
        with open(path, "rb") as f:
            return b"\0" not in f.read(8192)
    except OSError:
        return False


def _ok_file(p):
    if SECRET.search(p.name):
        return False
    if p.is_symlink():
        return True
    try:
        return p.is_file() and p.stat().st_size <= MAX_FILE and _is_text(p)
    except OSError:
        return False


def _is_profile(d):
    try:
        names = {e.name for e in d.iterdir()}
    except OSError:
        return True
    if names & PROFILE_MARKERS:
        return True
    # Chromium-style apps keep the markers one level down (Default/, Profile 1/)
    for sub in ("Default", "Profile 1"):
        try:
            if {e.name for e in (d / sub).iterdir()} & PROFILE_MARKERS:
                return True
        except OSError:
            pass
    return False


def _too_big(d):
    total = 0
    for root, dirs, files in os.walk(d):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
            if total > MAX_DIR:
                return True
    return False


def _files_in(d):
    out = []
    for root, dirs, files in os.walk(d):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS and not SECRET.search(x)
                         and not _is_profile(Path(root, x)))
        # symlinked folders show up in dirs; keep the link itself, not what's behind it
        for x in [x for x in dirs if Path(root, x).is_symlink()]:
            dirs.remove(x)
            out.append(Path(root, x))
        out += [Path(root, f) for f in sorted(files) if _ok_file(Path(root, f))]
    return out


def tracked_files():
    """Every file that counts as yours, found fresh each time (see the module docstring)."""
    out = []
    for root in ROOTS:
        base = HOME / root
        if not base.is_dir():
            continue
        if root != ".config":
            out += _files_in(base)
            continue
        for entry in sorted(base.iterdir()):
            if entry.is_symlink() or entry.is_file():
                if _ok_file(entry):
                    out.append(entry)
            elif entry.is_dir() and not SECRET.search(entry.name) and entry.name not in SKIP_DIRS \
                    and not _is_profile(entry) and not _too_big(entry):
                out += _files_in(entry)
    return out


def head():
    rc, out = git("rev-parse", "--verify", "-q", "HEAD")
    return out.strip() if rc == 0 else None


def snapshot(message, tag=None):
    """Commit the current state of your files (only if something changed); tag it. -> commit id or None"""
    if not ensure_repo():
        return None
    files = {str(p.relative_to(HOME)) for p in tracked_files()}
    _, indexed = git("ls-files", "-z")
    # files that are still there but no longer count as yours (grew too big, look like a secret now)
    dropped = [f for f in indexed.split("\0") if f and f not in files and (HOME / f).exists()]
    if dropped:
        git("rm", "-q", "--cached", "--pathspec-from-file=-", "--pathspec-file-nul", data="\0".join(dropped).encode())
    if files:
        git("add", "--pathspec-from-file=-", "--pathspec-file-nul", data="\0".join(sorted(files)).encode())
    git("add", "-u")  # deletions of files it already had
    if head() is None or git("diff", "--cached", "--quiet")[0] != 0:
        git("commit", "-q", "--allow-empty", "-m", message)
    if tag:
        git("tag", "-f", tag)
    return head()


def tag_time(tag):
    rc, out = git("log", "-1", "--format=%ct", tag)
    return datetime.fromtimestamp(int(out), timezone.utc) if rc == 0 and out.strip() else None


def mark_good():
    """Called when a check found nothing wrong: the reference point for "what changed since it worked"."""
    return snapshot("checked: nothing wrong", tag="good")


def changed_since(tag="good"):
    """Your files that changed since the last good check: [(status letter, path relative to home)].
    Call after snapshot(), which brings the history up to date."""
    if tag_time(tag) is None:
        return []
    rc, out = git("diff", "--name-status", "--no-renames", tag, "HEAD")
    if rc != 0:
        return []
    return [(line.split("\t", 1)[0][:1], line.split("\t", 1)[1]) for line in out.splitlines() if "\t" in line]


def fix_runs():
    """Fix runs that can be undone, newest first."""
    _, out = git("tag", "-l", "fix/*", "--sort=-creatordate")
    return [t[4:] for t in out.split()]


def undo(run_id=None):
    """Put back every file a fix run changed, as it was before the run. Files it created are moved
    to ~/.local/state/update-check/undone/<run>/. Files you've edited since are left alone.
    -> (run id, [what was done to each file]) or (None, [reason])"""
    runs = fix_runs()
    if not runs:
        return None, ["No fix runs to undo."]
    run_id = run_id or runs[0]
    if run_id not in runs:
        return None, [f"No fix run {run_id}. There are: {', '.join(runs[:8])}"]
    pre, post = f"pre/{run_id}", f"fix/{run_id}"
    _, out = git("diff", "--name-status", "--no-renames", pre, post)
    done = []
    for line in out.splitlines():
        st, path = line.split("\t", 1)
        target = HOME / path
        if git("diff", "--quiet", post, "--", path)[0] != 0 and (target.exists() or st != "D"):
            done.append(f"left alone (you changed it after the fix): ~/{path}")
            continue
        if st[0] in "MD":
            git("checkout", pre, "--", path)
            done.append(f"put back: ~/{path}")
        elif st[0] == "A" and target.exists():
            dest = UNDONE / run_id / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), dest)
            done.append(f"moved to {dest}: ~/{path} (the fix had created it)")
    snapshot(f"undid fix run {run_id}")
    git("tag", "-d", post)
    return run_id, done or ["That run didn't change any files."]


def history_log(path):
    _, out = git("log", "--format=%h %cd %s", "--date=format:%a %d %b %H:%M", "-n", "20", "--", path)
    return out


def history_show(rev, path):
    return git("show", f"{rev}:{path}")[1]


# ---- why it broke ----------------------------------------------------------------------------------

def _mentions(text, word):
    return len(word) > 2 and re.search(rf"(?<![\w.-]){re.escape(word)}(?![\w-])", text) is not None


def explain(what, changes, changed_files, good_at=None):
    """Why a problem appeared, in plain words, from what changed since the last good check.
    changes: package changes (update-check's Change tuples); changed_files: from changed_since()."""
    reasons = []
    verbs = {"M": "edited", "A": "added", "D": "deleted"}
    for st, path in changed_files:
        if path in what or _mentions(what, Path(path).name):
            reasons.append(f"you {verbs.get(st, 'changed')} ~/{path} since the last check that found nothing wrong")
    recent = [c for c in changes if good_at is None or c.time >= good_at]
    for c in recent:
        if _mentions(what, c.name):
            reasons.append(_describe(c))
    if not reasons:
        key = [c for c in recent if KEY_PACKAGES.search(c.name)]
        if key:
            names = ", ".join(_describe(c) for c in key[:3]) + (f" and {len(key) - 3} more" if len(key) > 3 else "")
            reasons.append(f"most likely the update ({names})")
    out = []
    for r in reasons:
        if r not in out:
            out.append(r)
    return "; ".join(out[:3]) or None


def _describe(c):
    when = c.time.astimezone().strftime("%a %d %b")
    if c.action == "removed":
        return f"{c.name} was removed ({when})"
    if c.action == "installed":
        return f"{c.name} was installed ({when})"
    if c.old and c.new and c.old != c.new:
        return f"{c.name} went from {c.old} to {c.new} ({when})"
    return f"{c.name} was {c.action} ({when})"


# ---- Claude ----------------------------------------------------------------------------------------

# Off unless you turn it on: nothing in update-check calls ai_fix() at the moment (see the README).
AI_DEFAULTS = {"enabled": False, "model": "claude-opus-5-5", "budget_usd": 3.0, "timeout_minutes": 20}
EDITABLE = ROOTS
ALLOWED = ["Read", "Glob", "Grep"]
ALLOWED += [f"{tool}(~/{root}/**)" for root in EDITABLE for tool in ("Edit", "Write")]
ALLOWED += [f"Bash({c}:*)" for c in (
    # looking
    "cat", "ls", "head", "tail", "grep", "rg", "find", "stat", "file", "diff", "wc", "which", "readlink",
    "realpath", "sort", "uniq", "cut", "sed -n", "pacman -Q", "pacman -F", "pacman -Si", "pacman -Ss", "expac",
    "yay -Qu", "yay -Si", "ldd", "readelf", "nm", "journalctl", "coredumpctl list", "coredumpctl info",
    "systemctl status", "systemctl is-", "systemctl list-", "pgrep", "ps", "luac -p", "bash -n", "sh -n",
    "python3 -m py_compile", "qs", "quickshell", "flatpak list", "flatpak info", "arch-update --check",
    "update-check --selftest", "update-check --after", "update-check --history",
    # putting right (your own services, the shells, file modes)
    "systemctl --user", "hyprctl", "caelestia-patch", "chmod", "mkdir", "cp", "ln")]
# the checker by its full path too (Claude often types it that way)
ALLOWED += [f"Bash({prefix}/.local/bin/update-check --{sub}:*)" for prefix in ("~", str(HOME))
            for sub in ("selftest", "after", "history")]
DENIED = [f"Bash({c}:*)" for c in ("sudo", "pkexec", "su", "doas", "rm", "shred", "dd", "mkfs", "pacman -S", "pacman -R",
                                   "pacman -U", "yay -S", "yay -R", "paru", "makepkg", "reboot", "poweroff",
                                   "systemctl reboot", "systemctl poweroff", "systemctl suspend", "git push", "curl", "wget")]

SYSTEM = """You are the repair step of the user's Arch Linux update checker, running unattended right after its
own checks and built-in fixes. You get the problems still left, and you fix as many as you can, properly.

Rules:
- Find the root cause first (logs, the files involved, what the update changed, earlier versions of the user's
  files), then make the smallest change that fixes it. Keep the user's own customizations: adapt their configs
  to the new upstream behaviour rather than resetting anything to defaults.
- You may only edit files under ~/.config, ~/.local/bin, ~/.local/share/applications and ~/.local/share/arch-kit.
  Every file there is snapshotted before you start, so the user can undo all of it with one command; you don't
  need to make backups.
- Never use sudo, never delete files, never install, remove, downgrade or rebuild packages, never reboot. Anything
  that needs root or a rebuild goes into needs_you with the exact command and a plain explanation.
- Verify each fix (re-run the failing check, `update-check --selftest`, read the log again). Only mark fixed=true
  when you saw it working.
- Don't touch problems you weren't given, and don't edit ~/.claude (read it for background only).
- Write for someone who isn't a Linux expert: short, plain sentences, no jargon without a word of explanation.
- lessons: up to 3 short rules worth remembering about this particular system for next time (empty if none)."""

SCHEMA = {
    "type": "object", "additionalProperties": False, "required": ["fixes", "needs_you", "lessons"],
    "properties": {
        "fixes": {"type": "array", "items": {
            "type": "object", "additionalProperties": False, "required": ["problem", "cause", "did", "files", "fixed"],
            "properties": {
                "problem": {"type": "string", "description": "the problem, as given"},
                "cause": {"type": "string", "description": "why it broke, one or two plain sentences"},
                "did": {"type": "string", "description": "what you changed or ran, plainly"},
                "files": {"type": "array", "items": {"type": "string"}, "description": "files you changed"},
                "fixed": {"type": "boolean", "description": "true only if you verified it works now"}}}},
        "needs_you": {"type": "array", "items": {
            "type": "object", "additionalProperties": False, "required": ["problem", "cause", "command", "why"],
            "properties": {
                "problem": {"type": "string"}, "cause": {"type": "string"},
                "command": {"type": "string", "description": "exact command the user should run"},
                "why": {"type": "string", "description": "what the command does and why it's needed"}}}},
        "lessons": {"type": "array", "items": {"type": "string"}}}}


def ai_settings(config):
    s = dict(AI_DEFAULTS)
    s.update({k: v for k, v in (config.get("ai") or {}).items() if k in AI_DEFAULTS})
    return s


def claude_bin():
    return shutil.which("claude", path=os.environ.get("PATH", "") + os.pathsep + str(HOME / ".local/bin"))


def _key(what):
    """Same problem, same key, even when a number or path in it changed."""
    return hashlib.sha1(re.sub(r"\d+", "#", what).encode()).hexdigest()[:16]


def load_attempts():
    try:
        return json.loads(ATTEMPTS.read_text())
    except (OSError, ValueError):
        return {}


def worth_trying(what, attempts, newest_change):
    """Retry a problem Claude already tried only after a new update, or after a week."""
    t = attempts.get(_key(what))
    if not t:
        return True
    tried = datetime.fromtimestamp(t, timezone.utc)
    return (newest_change is not None and newest_change > tried) or (datetime.now(timezone.utc) - tried).days >= 7


def memory_dir():
    """Claude Code's notes about this desktop, if there are any (read-only background for the fixer)."""
    d = HOME / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(HOME)) / "memory"
    return d if (d / "MEMORY.md").exists() else None


def build_prompt(problems, changes, changed_files):
    lines = ["Problems still left after the built-in checks and fixes:"]
    for i, p in enumerate(problems, 1):
        lines.append(f"{i}. {p['what']}")
        if p.get("cause"):
            lines.append(f"   The checker's guess at why: {p['cause']}")
        if p.get("tried"):
            lines.append(f"   Built-in fix tried: `{p['tried']}` -> {p.get('outcome') or 'no result'}")
    lines.append("")
    if changes:
        lines.append(f"Package changes since the last check that found nothing wrong ({len(changes)}, newest last):")
        for c in changes[-80:]:
            lines.append(f"  {c.time.astimezone():%Y-%m-%d %H:%M} {c.action} {c.name} {c.old or ''} {'-> ' + c.new if c.new and c.old else c.new or ''}".rstrip())
    else:
        lines.append("No package changes since the last check that found nothing wrong.")
    lines.append("")
    if changed_files:
        lines.append(f"The user's files that changed since then ({len(changed_files)}; M edited, A added, D deleted):")
        lines += [f"  {st} ~/{path}" for st, path in changed_files[:120]]
        lines.append("  (earlier versions: `update-check --history PATH` lists them; "
                     "`update-check --history REV PATH` prints one)")
        lines.append("")
    if LESSONS.exists():
        lines.append("Lessons from earlier repair runs on this system:")
        lines += LESSONS.read_text(errors="replace").strip().splitlines()[-40:]
        lines.append("")
    mem = memory_dir()
    if mem:
        lines.append(f"Background notes about how this desktop is set up: {mem}/MEMORY.md (an index; read the "
                     "notes that relate to the problems). Read only, don't edit them.")
    lines.append("Answer with the JSON the schema asks for: every problem above goes into fixes or needs_you.")
    return "\n".join(lines) + "\n"


def parse_answer(out):
    try:
        res = json.loads(out)
    except ValueError:
        return None, None
    if not isinstance(res, dict) or res.get("is_error"):
        return None, res if isinstance(res, dict) else None
    ans = res.get("structured_output")
    if not isinstance(ans, dict):
        try:
            ans = json.loads(res.get("result", ""))
        except (TypeError, ValueError):
            ans = None
    if not isinstance(ans, dict):
        return None, res
    ans.setdefault("fixes", [])
    ans.setdefault("needs_you", [])
    ans.setdefault("lessons", [])
    return ans, res


def ai_fix(problems, changes, changed_files, config, newest_change=None, say=print):
    """problems: [{"what", "cause", "tried", "outcome"}]. Snapshot, hand them to Claude, snapshot again.
    -> (run dict or None, reason when None). The run is also saved in ~/.local/state/update-check/runs/."""
    s = ai_settings(config)
    if not s["enabled"]:
        return None, "Claude repair is turned off ([ai] enabled = false in ~/.config/update-check/config.toml)"
    if os.environ.get(NO_AI):
        return None, "running inside a Claude repair already"
    exe = claude_bin()
    if not exe:
        return None, "the claude command isn't installed"
    attempts = load_attempts()
    todo = [p for p in problems if worth_trying(p["what"], attempts, newest_change)]
    if not todo:
        return None, "Claude already tried these since the last update and couldn't fix them"
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    snapshot(f"before fix run {run_id}", tag=f"pre/{run_id}")
    say(f"Asking Claude to look at {len(todo)} problem{'s' * (len(todo) != 1)} (it can take a few minutes)…")
    cmd = [exe, "-p", "--model", str(s["model"]), "--permission-mode", "dontAsk",
           "--allowedTools", *ALLOWED, "--disallowedTools", *DENIED,
           "--append-system-prompt", SYSTEM, "--strict-mcp-config", "--setting-sources", "",
           "--no-session-persistence", "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
           "--max-budget-usd", str(s["budget_usd"])]
    env = dict(os.environ, **{NO_AI: "1"})
    error = None
    try:
        p = subprocess.run(cmd, input=build_prompt(todo, changes, changed_files), capture_output=True, text=True,
                           timeout=float(s["timeout_minutes"]) * 60, cwd=HOME, env=env)
        ans, raw = parse_answer(p.stdout)
        if ans is None:
            error = (raw or {}).get("result") or (p.stderr or p.stdout).strip()[-400:] or f"exit code {p.returncode}"
    except subprocess.TimeoutExpired:
        ans, raw, error = None, None, f"Claude took longer than {s['timeout_minutes']} minutes"
    now = datetime.now(timezone.utc).timestamp()
    for p_ in todo:
        attempts[_key(p_["what"])] = now
    STATE.mkdir(parents=True, exist_ok=True)
    ATTEMPTS.write_text(json.dumps(attempts))
    snapshot(f"fix run {run_id}: Claude", tag=f"fix/{run_id}")
    _, changed = git("diff", "--name-only", "--no-renames", f"pre/{run_id}", f"fix/{run_id}")
    run = {"id": run_id, "time": datetime.now().isoformat(timespec="seconds"), "problems": [p_["what"] for p_ in todo],
           "fixes": (ans or {}).get("fixes", []), "needs_you": (ans or {}).get("needs_you", []),
           "files_changed": [f for f in changed.splitlines() if f], "error": error,
           "cost_usd": (raw or {}).get("total_cost_usd")}
    if not run["files_changed"]:
        git("tag", "-d", f"fix/{run_id}")  # nothing to undo
    lessons = [l.strip() for l in (ans or {}).get("lessons", []) if l.strip()]
    if lessons:
        old = LESSONS.read_text(errors="replace").splitlines() if LESSONS.exists() else []
        LESSONS.write_text("\n".join((old + [f"- {datetime.now():%Y-%m-%d}: {l}" for l in lessons])[-60:]) + "\n")
    RUNS.mkdir(parents=True, exist_ok=True)
    (RUNS / f"{run_id}.json").write_text(json.dumps(run, indent=1))
    return run, ""
