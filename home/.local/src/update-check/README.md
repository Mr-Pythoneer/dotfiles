# update-check

Tells me whether this Arch system needs updating and what to watch out for. After an update,
it works out what broke and fixes it. A self-test also checks that everything this desktop starts
and runs is actually there. Updating itself is done by `arch-update` (in `~/.local/bin`).

`~/.local/bin/update-check` is a symlink to `update-check` in this repo.

## Usage

```
update-check                     check now (repos, AUR, Flatpak, Arch news, health, self-test),
                                 fix what's broken, then offer to run arch-update
update-check --login             run by Hyprland at login: check, fix what needs nothing from you, one notification
update-check --daily             run by the 07:00 systemd timer: same, skips if already checked today, waits for unlock
update-check --show              print the last report (what the notification's buttons open)
update-check --after             post-update check + self-test (offline, read-only)
update-check --after --fix       the same, then fix everything it found (see "Fixing")
update-check --after --fix --ask the same, but confirm each fix
update-check --selftest [--fix]  only the self-test
update-check --history           recent snapshots of your configs and scripts (see "Your files' history")
update-check --history FILE      that file's saved versions;  --history REV FILE prints one
update-check --restore FILE [REV]  put a file back as it was (default: the last check that found nothing wrong)
update-check --snapshot MESSAGE  take a snapshot now (arch-update does this before every update)
update-check --undo [RUN]        put back everything Claude's last (or that) repair run changed
```

## Post-update check (`--after`)

Works out whether the system was updated since the last time I looked, and checks for anything
the update may have broken. The checks are read-only and need no network.

The report starts with a short summary: updated or not, reboot needed or not, how many problems,
and what the self-test covered. Then it lists each problem with the command that fixes it, then
notes worth knowing, then the list of package changes.

| Check | How |
|---|---|
| Updated since last check | `[ALPM] upgraded/installed/removed/…` lines in `/var/log/pacman.log` newer than the timestamp in `~/.local/state/update-check/last-seen-update`. On the first run it reports the last full system upgrade. |
| Reboot needed | Compares `uname -r` with the installed version of the kernel package you're running (`linux`, `linux-lts`, `linux-zen`, …). Also flags systemd, glibc, dbus, the graphics stack (mesa, vulkan, nvidia, libdrm, wayland) and microcode/firmware updated after boot. |
| Failed services | `systemctl --failed` and `systemctl --user --failed` (the TPM units that fail every boot on this machine are ignored). |
| Journal errors | `journalctl -b -p err`, as a count per program with a sample message. This is listed under "worth knowing" and isn't counted as a problem. |
| Unmerged config files | `.pacnew` / `.pacsave` under `/etc`. |
| Packages needing a rebuild | `checkrebuild`, if installed. It takes a few minutes. A library `ldd` can't find but the package ships itself isn't missing: e.g. Zen's DRM plugin (`gmp-clearkey/0.1/`) needs `libmozsqlite3.so` from two folders up, which the browser has already loaded. A package flagged only for that is listed under "worth knowing", not as a problem; the same rule applies to your own builds. |
| Your own builds | Each entry in the config file: `ldd` on every ELF file it owns, looking for `not found`. Then the Qt check: `readelf -V` shows which Qt 6.x it needs and whether it uses Qt's private API. If it uses the private API and was built before the installed `qt6-base` arrived, it's flagged. Built before that but using only the public API, it's a note. If the entry has a `check` command, that must pass too. |
| Prebuilt (`-bin`) packages | These ship upstream's binaries, so rebuilding one only repackages the same files. When one is flagged, the report names the exact missing library from `ldd` (and the file that needs it), and the fix is a read-only check for a newer version (`yay -Qua`, which needs internet). Missing files are restored from yay's cache of the same version. `--rebuild` is only offered for packages that compile from source. A `rebuild` set in the config still wins. |
| Broken package files | `pacman -Qkq`. Files pacman can't see without root (e.g. `/boot`) are counted separately; they aren't treated as missing. |

If a pacman/yay transaction is running while you check, it says so, because libraries can look
missing while files are being replaced.

When there's been an update since the last report, the login/07:00 run does all of these;
otherwise only the quick ones (reboot, config files, failed services) plus the self-test. The
"seen" timestamp moves forward whenever a report covering the new changes has been shown or sent
as a notification.

## Self-test

Checks that everything is actually there. It's offline, read-only, and takes well under a second.

| What | How |
|---|---|
| Hyprland config | `hyprland.lua` and every file it `require`s exist and parse (`luac -p`). Every `exec_cmd(...)` (autostart and keybinds, with `local` string variables filled in, including inside `sh -c '…'`) runs a program that's installed, or a script that exists and is executable. File paths written in the config exist; several paths on one line are alternatives, so one existing is enough. (`Hyprland --verify-config` isn't used: it segfaults with the Lua config.) |
| Your services | Every `Exec…=` program in `~/.config/systemd/user/*.service` exists, and nothing enabled points at a deleted unit file. |
| Your scripts | Every script in `~/.local/bin` (not backups) has its interpreter installed and parses (`bash -n` / `sh -n`, or compiling the Python). The commands it runs are installed. For shell scripts that means a quote-, comment- and heredoc-aware scan; for Python, `run([...])`-style calls. Commands a script checks for first (`command -v x`, `shutil.which("x")`) count as optional. |
| Config files | Caelestia's `~/.config/caelestia/*.json` and this tool's config parse. |
| Caelestia copy | `~/.config/quickshell/caelestia` must be exactly what `caelestia-patch` would make now: the installed Caelestia with your patches applied. It's checked by applying the patches to a temp copy and comparing every file. This catches a Caelestia update you haven't re-patched, a patch that isn't applied, missing files, and a patch that no longer applies to the new Caelestia (which needs redoing by hand). |
| Shells | `quickshell --private-check-compat` (Quickshell matches Qt). Inside the desktop session: every Quickshell config your Hyprland config starts (`qs -c NAME`, `caelestia shell`) is running, asked from Quickshell itself (`qs list --all --json`), because after a crash Quickshell restarts a shell in place as plain `/usr/bin/quickshell` and a command-line match misses it. The fix starts it through Hyprland with `-n`, so it can never become a second copy. Every running shell's log is read for lines saying part of it failed to load (`is not a type`, `module … is not installed`, `Cannot assign to non-existent property`…); the usual noise (`TypeError … of null` while windows rebuild, missing icons) doesn't count. A new Quickshell config is covered as soon as Hyprland starts it. |
| Hyprland's own check | `hyprctl configerrors`: options an update renamed or removed. |
| Python imports | Every module your Python scripts in `~/.local/bin` import can be found by their interpreter (a Python upgrade drops modules installed with pip for the old version). Imports inside `try: … except ImportError` are optional; modules next to a script (a symlink into a repo) count as there. |
| Launchers and autostart | Every `.desktop` file in `~/.local/share/applications` and `~/.config/autostart` (not `Hidden=true` ones) runs a program that exists. |
| Things you built | Programs and plugins in `~/.local/bin` and `~/.local/lib` that aren't packages still find all their libraries (`ldd`). |

None of these use a list of your apps: they look at what's there each time, so new apps, scripts, launchers
and shells are checked from the moment they exist.

If pacman's file lists are downloaded (`sudo pacman -Fy`), a missing command also names the package that has it.

## Your files' history

Every small text file under `~/.config`, `~/.local/bin`, `~/.local/share/applications` and
`~/.local/share/arch-kit` is kept in a private git history: `~/.local/state/update-check/history.git`,
whose work tree is your home. It's never pushed anywhere, and nothing outside those folders is in it.
What counts is worked out fresh at every snapshot, so a new app's config is included the first time it
appears. Left out: app profiles (folders with browser-style caches or Mozilla profile files: Chrome,
Discord, Bitwarden, Zen, Thunderbird…), folders over 20 MB, files over 256 KB, binary files, and anything
named like a secret (token, password, key, auth, cookie…).

Snapshots are taken by `arch-update` before it updates and by every check that finds problems; a check
that finds nothing wrong tags its state `good`. That's what makes the next part possible.

## Why it broke

Each problem in a report gets a `why:` line, from what changed since the last check that found nothing wrong:

- one of your files it mentions changed: "you edited ~/.config/hypr/hyprland.lua since the last check…";
- a package it mentions was updated or removed: "quickshell-pinned went from 0.3.1-1 to 0.3.1-2 (Sun 18 Oct)";
- otherwise, if the update touched something that often breaks desktop pieces (Qt, Hyprland, Quickshell,
  Python, glibc, Mesa, PipeWire…): "most likely the update (qt6-base went from … to …)".

To see or undo your own changes: `update-check --history FILE`, then `update-check --restore FILE REV`
(the version you had is snapshotted first, so a restore can be undone the same way).

## Claude repair

Problems the built-in fixes can't solve (no fix exists, or the fix failed or didn't hold) go to Claude
Code (`claude -p`), at login, at 7:00 and in the fix terminal, once the built-in fixes are done. Turn
it on or off with `[ai] enabled` in `~/.config/update-check/config.toml` (off if the section is missing).

- It gets the problems, what the built-in fixes tried, the package changes and your file changes since
  the last good check, lessons from earlier runs (`~/.local/state/update-check/lessons.md`), and
  Claude Code's notes about this desktop to read.
- It may edit files only under `~/.config`, `~/.local/bin`, `~/.local/share/applications` and
  `~/.local/share/arch-kit`, which are snapshotted right before (`pre/<run>`) and after (`fix/<run>`).
  It runs only commands on an allow-list (looking around, `systemctl --user`, `hyprctl`, `qs`,
  `caelestia-patch`…); sudo, rm, installing, removing, building and rebooting are refused. Anything
  needing root comes back as a command for you, offered one by one (y/N) in the fix terminal.
- It answers in a fixed JSON form: per problem, why it broke, what it did, which files it changed,
  and whether it saw it working. The checker then checks everything again; a fix only counts when the
  problem is really gone.
- At most `budget_usd` per run (default $3) and `timeout_minutes`. A problem it couldn't fix isn't
  sent again until there's a new update, or a week has passed.
- Undo: `update-check --undo [RUN]` (or the notification's "Undo Claude's changes" button) puts back every
  file the run changed. Files it created are moved to `~/.local/state/update-check/undone/<run>/`, and
  files you edited after the run are left alone.

## Fixing

Every problem that has a fix carries three things:

- the fix itself;
- the follow-ups it needs before the fix is actually in use. These come from the config's `after`,
  e.g. `caelestia-patch` (which restarts the shell) after rebuilding Quickshell or Caelestia;
- a re-check, the same check that found it, run again afterwards.

`--fix` runs every fix in order. Then it runs each follow-up once (only if its fix worked), then
re-checks each problem and reports **fixed**, **STILL BROKEN after the fix**, or **done** (when
there's nothing to re-check, e.g. the newer-version check for a `-bin` package). Two checks that
find the same breakage (e.g. "Quickshell built before Qt" and "Quickshell doesn't match Qt") become
one entry, so the fix runs once.

Where it runs automatically:

- **`arch-update`** runs `update-check --after --fix` when it finishes.
- **Login / 07:00**: fixes that need nothing from you run in the background: restarting your own
  services, `caelestia-patch`, starting the shell, the `-bin` newer-version check. Their output
  goes to `~/.cache/update-check/fix.log`. If anything is left that needs your password, a rebuild
  or answers (`sudo …`, `arch-update --build-…`, `yay -S`, `pacdiff`), a terminal opens and runs
  `update-check --after --fix` for those. If a game or video is fullscreen, the terminal waits and
  opens once you leave fullscreen (`update-check --fix-later`), so it doesn't sit hidden behind it
  waiting for your password. The report lists what was fixed under "Fixed automatically" and shows
  the outcome under anything still left. The notification says the same, e.g.
  "fixed 1 problem automatically".
- **A plain `update-check`** in a terminal fixes what it finds before offering `arch-update`.

### Limits

- **Never reboots on its own.** At the end of `--fix` in a terminal it asks "Reboot now? [y/N]".
- **sudo still asks for your password.** It runs in a terminal, never silently.
- **Nothing is deleted.** `pacdiff` asks about each file itself.
- **Nothing is downgraded.** Files missing from a repo package are only fixed by reinstalling the
  exact installed version: from the repo if it has the same version, else from pacman's (or
  yay's) cache. If neither has it, no command is offered.
- **The checks change nothing**; only `--fix` (and the login/07:00 auto-fix) runs commands.
- **Missing tools are skipped, not fatal.** A missing tool, an unreadable file or a denied
  permission skips that check with a note instead of crashing.
- **Some problems have no fix to run.** That covers a script calling a missing command, a broken
  JSON file, or a patch that no longer applies. They're reported for you to sort out.

## Config

`~/.config/update-check/config.toml` (copy `config.example.toml`). It lists the things you build
yourself, in the order they should be rebuilt:

```toml
[[custom]]
package = "quickshell-pinned"                            # a pacman package: all its files are checked
rebuild = "arch-update --build-local quickshell-pinned"  # the fix (default: yay -S --rebuild <pkg>;
                                                         # for -bin packages: check for a newer version)
after = ["caelestia-patch"]                              # needed once the rebuild worked (run once, at the end)
check = "quickshell --private-check-compat"              # must pass when it works; also re-checked after the fix

[[custom]]
name = "hymission (window overview plugin)"
files = ["~/.local/lib/hyprland/libhymission.so"]        # files not in any package
rebuild = "arch-update --build-hymission"
```

The `rebuild` and `after` commands are also used when `checkrebuild` or the Quickshell check flags
one of these packages.

## Dependencies

Python 3.11+ (standard library only), pacman, systemd. Optional:

- `rebuild-detector` (`checkrebuild`): the rebuild check. If it's missing, the report says so.
- `binutils` (`readelf`): the Qt version check.
- `pacman-contrib` (`pacdiff`): the fix for `.pacnew` files.
- `lua` (`luac`): the Hyprland config syntax check.
- `patch`: the Caelestia copy check.
- `yay`, `flatpak`, `fakeroot`, `notify-send`, `kitty`: the update check / notification / fix terminal.

## Tests

```
python3 -m unittest discover -s tests
```

They cover:
- pacman.log parsing (including old-format lines and garbage), "what's new since last seen",
  kernel-version mapping and the reboot-needed logic, all from sample log text;
- which fix `-bin` packages get (`checkrebuild` and `ldd` faked);
- the script scanner (quotes, comments, heredocs, `$(…)`, case patterns, `sudo -u x cmd`) and the
  Hyprland Lua parsing;
- the fix runner: follow-ups once and only after success, re-check outcomes, never rebooting, the
  background/terminal split, and the terminal waiting while something is fullscreen;
- the Caelestia copy check, on a temp copy with a real patch;
- (`test_smart.py`) what goes to Claude and when its fix counts (Claude faked), which files count as yours (profiles, secrets, big and binary files left out), the
  history (snapshots, changes since the good check, dropping files that stop counting, undo sparing
  your later edits), the why-it-broke wording, the discovery checks (shell start commands, shell log
  errors vs noise, Hyprland config errors, Python imports, launchers, autostarted shells).
