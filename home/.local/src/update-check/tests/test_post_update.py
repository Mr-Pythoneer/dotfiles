"""Tests for the post-update check: pacman.log parsing and the reboot-needed logic.

Run: python3 -m unittest discover -s tests   (from the repo directory)
"""
import importlib.machinery
import importlib.util
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

# the script has no .py extension, so load it by path
_path = str(Path(__file__).resolve().parent.parent / "update-check")
_loader = importlib.machinery.SourceFileLoader("update_check", _path)
_spec = importlib.util.spec_from_loader("update_check", _loader)
uc = importlib.util.module_from_spec(_spec)
_loader.exec_module(uc)

EDT = timezone(timedelta(hours=-4))

SAMPLE_LOG = """\
[2026-10-04T10:26:58-0400] [PACMAN] Running 'pacman -S -y -u --config /etc/pacman.conf --'
[2026-10-04T10:26:58-0400] [PACMAN] synchronizing package lists
[2026-10-04T10:27:00-0400] [PACMAN] starting full system upgrade
[2026-10-04T10:27:10-0400] [ALPM] transaction started
[2026-10-04T10:27:11-0400] [ALPM] upgraded linux (7.2.7.arch1-1 -> 7.2.8.arch1-2)
[2026-10-04T10:27:11-0400] [ALPM] installed newdep (1.0-1)
[2026-10-04T10:27:12-0400] [ALPM] removed olddep (0.9-3)
[2026-10-04T10:27:13-0400] [ALPM] transaction completed
[2026-10-04T10:27:14-0400] [ALPM-SCRIPTLET] ==> Building image from preset: /etc/mkinitcpio.d/linux.preset
[2026-10-04T18:36:59-0400] [ALPM] upgraded caelestia-shell-topbar (2.5.0.pr2076-1 -> 2.5.0.pr2076-2)
[2026-10-09T21:08:32-0400] [PACMAN] starting full system upgrade
[2026-10-09T21:18:05-0400] [ALPM] upgraded qt6-base (6.11.2-3 -> 6.12.0-2)
[2026-10-09T21:18:06-0400] [ALPM] upgraded glibc (2.42-1 -> 2.42-2)
[2026-10-09T21:18:07-0400] [ALPM] reinstalled fcitx5-qt (5.1.16-2)
[2026-10-09T21:18:08-0400] [ALPM] downgraded foo (2.0-1 -> 1.9-1)
this line is garbage
[not-a-date] [ALPM] upgraded bar (1 -> 2)
"""


def t(s):
    return datetime.fromisoformat(s)


class ParseLog(unittest.TestCase):
    def setUp(self):
        self.changes, self.upgrades = uc.parse_pacman_log(SAMPLE_LOG.splitlines(keepends=True))

    def test_finds_every_package_change(self):
        self.assertEqual([(c.action, c.name) for c in self.changes], [
            ("upgraded", "linux"), ("installed", "newdep"), ("removed", "olddep"),
            ("upgraded", "caelestia-shell-topbar"), ("upgraded", "qt6-base"), ("upgraded", "glibc"),
            ("reinstalled", "fcitx5-qt"), ("downgraded", "foo"),
        ])

    def test_versions(self):
        by = {c.name: c for c in self.changes}
        self.assertEqual((by["linux"].old, by["linux"].new), ("7.2.7.arch1-1", "7.2.8.arch1-2"))
        self.assertEqual((by["newdep"].old, by["newdep"].new), ("", "1.0-1"))
        self.assertEqual((by["olddep"].old, by["olddep"].new), ("0.9-3", ""))
        self.assertEqual((by["fcitx5-qt"].old, by["fcitx5-qt"].new), ("5.1.16-2", "5.1.16-2"))
        self.assertEqual((by["foo"].old, by["foo"].new), ("2.0-1", "1.9-1"))

    def test_times_keep_their_offset(self):
        self.assertEqual(self.changes[0].time, t("2026-10-04T10:27:11-04:00"))
        self.assertEqual(self.upgrades, [t("2026-10-04T10:27:00-04:00"), t("2026-10-09T21:08:32-04:00")])

    def test_old_log_format_without_offset(self):
        changes, _ = uc.parse_pacman_log(["[2019-03-01 12:00] [ALPM] upgraded zlib (1.2.11-3 -> 1.2.11-4)\n"])
        self.assertEqual(len(changes), 1)
        self.assertIsNotNone(changes[0].time.tzinfo)  # comparable with the newer, offset-carrying lines

    def test_empty_log(self):
        self.assertEqual(uc.parse_pacman_log([]), ([], []))


class NewChanges(unittest.TestCase):
    def setUp(self):
        self.changes, self.upgrades = uc.parse_pacman_log(SAMPLE_LOG.splitlines(keepends=True))

    def test_first_run_reports_the_last_full_upgrade_onwards(self):
        new = uc.new_changes(self.changes, self.upgrades, None)
        self.assertEqual([c.name for c in new], ["qt6-base", "glibc", "fcitx5-qt", "foo"])

    def test_only_changes_after_the_last_seen_one(self):
        new = uc.new_changes(self.changes, self.upgrades, t("2026-10-09T21:18:06-04:00"))
        self.assertEqual([c.name for c in new], ["fcitx5-qt", "foo"])

    def test_nothing_new(self):
        self.assertEqual(uc.new_changes(self.changes, self.upgrades, t("2026-10-09T21:18:08-04:00")), [])

    def test_last_seen_in_another_timezone(self):
        # same instant as 21:18:06-04:00
        new = uc.new_changes(self.changes, self.upgrades, t("2026-10-10T01:18:06+00:00"))
        self.assertEqual([c.name for c in new], ["fcitx5-qt", "foo"])

    def test_no_full_upgrade_in_log(self):
        changes, upgrades = uc.parse_pacman_log(["[2026-10-04T18:36:59-0400] [ALPM] installed x (1-1)\n"])
        self.assertEqual(uc.new_changes(changes, upgrades, None), [])


class KernelVersions(unittest.TestCase):
    def test_package_for_running_kernel(self):
        self.assertEqual(uc.kernel_package("7.2.8-arch1-2"), "linux")
        self.assertEqual(uc.kernel_package("6.12.50-1-lts"), "linux-lts")
        self.assertEqual(uc.kernel_package("6.10.5-zen1-1-zen"), "linux-zen")
        self.assertEqual(uc.kernel_package("6.10.5-hardened1-1-hardened"), "linux-hardened")

    def test_package_version_to_uname(self):
        self.assertEqual(uc.kernel_release("linux", "7.2.8.arch1-2"), "7.2.8-arch1-2")
        self.assertEqual(uc.kernel_release("linux-lts", "6.12.50-1"), "6.12.50-1-lts")
        self.assertEqual(uc.kernel_release("linux-zen", "6.10.5.zen1-1"), "6.10.5-zen1-1-zen")


class RebootNeeded(unittest.TestCase):
    BOOTED = t("2026-10-09T08:00:00-04:00")

    def changes(self, *lines):
        return uc.parse_pacman_log([l + "\n" for l in lines])[0]

    def test_up_to_date_kernel_and_nothing_since_boot(self):
        self.assertEqual(uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.8.arch1-2"}, [], self.BOOTED), [])

    def test_kernel_updated_but_not_rebooted(self):
        reasons = uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.9.arch1-1"}, [], self.BOOTED)
        self.assertEqual(len(reasons), 1)
        self.assertIn("linux 7.2.9.arch1-1", reasons[0])

    def test_lts_running_and_current(self):
        kernels = {"linux": "7.2.9.arch1-1", "linux-lts": "6.12.50-1"}
        # linux is newer than what's running, but you're on linux-lts, which is current
        self.assertEqual(uc.reboot_reasons("6.12.50-1-lts", kernels, [], self.BOOTED), [])

    def test_lts_running_and_outdated(self):
        reasons = uc.reboot_reasons("6.12.49-1-lts", {"linux-lts": "6.12.50-1"}, [], self.BOOTED)
        self.assertIn("linux-lts 6.12.50-1", reasons[0])

    def test_running_kernel_package_not_installed(self):
        self.assertEqual(uc.reboot_reasons("6.12.50-1-lts", {"linux": "7.2.8.arch1-2"}, [], self.BOOTED), [])

    def test_core_and_graphics_updated_since_boot(self):
        changes = self.changes(
            "[2026-10-09T21:18:06-0400] [ALPM] upgraded glibc (2.42-1 -> 2.42-2)",
            "[2026-10-09T21:18:07-0400] [ALPM] upgraded mesa (1:26.2.1-1 -> 1:26.2.2-1)",
            "[2026-10-09T21:18:07-0400] [ALPM] upgraded systemd-libs (259-1 -> 259-2)",
        )
        reasons = uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.8.arch1-2"}, changes, self.BOOTED)
        self.assertEqual(len(reasons), 2)
        self.assertIn("glibc, systemd-libs", reasons[0])
        self.assertIn("mesa", reasons[1])

    def test_core_updated_before_boot_is_fine(self):
        changes = self.changes("[2026-10-08T21:00:00-0400] [ALPM] upgraded systemd (259-1 -> 259-2)")
        self.assertEqual(uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.8.arch1-2"}, changes, self.BOOTED), [])

    def test_removed_or_unrelated_packages_dont_count(self):
        changes = self.changes(
            "[2026-10-09T21:00:00-0400] [ALPM] removed nvidia-utils (580-1)",
            "[2026-10-09T21:00:00-0400] [ALPM] upgraded systemd-ukify (259-1 -> 259-2)",  # not systemd itself
            "[2026-10-09T21:00:00-0400] [ALPM] upgraded firefox (140-1 -> 141-1)",
        )
        self.assertEqual(uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.8.arch1-2"}, changes, self.BOOTED), [])

    def test_unknown_boot_time_still_checks_the_kernel(self):
        changes = self.changes("[2026-10-09T21:00:00-0400] [ALPM] upgraded glibc (2.42-1 -> 2.42-2)")
        self.assertEqual(uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.8.arch1-2"}, changes, None), [])
        self.assertEqual(len(uc.reboot_reasons("7.2.8-arch1-2", {"linux": "7.2.9.arch1-1"}, changes, None)), 1)


class PrebuiltPackages(unittest.TestCase):
    """-bin packages: name the missing library and suggest a newer version, never --rebuild."""

    def fake_run(self, cmd, timeout=180, env=None):
        if cmd == ["checkrebuild"]:
            return 0, "foreign\tzen-browser-bin\nforeign\thymission-git\ncore\tsomelib\n", ""
        if cmd[0] == "ldd":
            return 0, "\tlibc.so.6 => /usr/lib/libc.so.6 (0x7f)\n\tlibicuuc.so.76 => not found\n", ""
        return 1, "", ""

    files = [Path("/opt/zen/zen")]  # what each flagged package owns

    def problems(self, custom=None):
        with mock.patch.object(uc, "run", self.fake_run), \
             mock.patch.object(uc.shutil, "which", lambda name: "/usr/bin/" + name), \
             mock.patch.object(uc, "package_files", lambda pkg: self.files), \
             mock.patch.object(uc, "elf_files", lambda files: files[:1]):
            found, self.notes = uc.checkrebuild_problems(custom or {})
        return {p.what.split()[0]: p for p in found}

    def test_library_the_package_ships_itself_is_not_missing(self):
        # Zen's DRM plugin needs libmozsqlite3.so from two folders up; ldd can't see it, the browser can
        self.files = [Path("/opt/zen/gmp-clearkey/0.1/libclearkey.so"), Path("/opt/zen/libicuuc.so.76")]
        self.assertEqual(self.problems(), {})
        self.assertEqual(len(self.notes), 3)
        self.assertIn("ship with zen-browser-bin itself", self.notes[0])

    def test_is_prebuilt(self):
        self.assertTrue(uc.is_prebuilt("visual-studio-code-bin"))
        self.assertFalse(uc.is_prebuilt("quickshell-pinned"))
        self.assertFalse(uc.is_prebuilt("bin-utils"))

    def test_bin_package_names_the_missing_library_and_checks_for_an_update(self):
        p = self.problems()["zen-browser-bin"]
        self.assertIn("libicuuc.so.76 (needed by /opt/zen/zen)", p.what)
        self.assertNotIn("--rebuild", p.fix)
        self.assertTrue(p.fix.startswith("yay -Qua"))  # read-only: lists updates, installs nothing

    def test_source_package_still_gets_a_rebuild(self):
        self.assertEqual(self.problems()["hymission-git"].fix, "yay -S --rebuild hymission-git")

    def test_rebuild_command_from_config_wins(self):
        p = self.problems({"zen-browser-bin": {"rebuild": "my-own-fix"}})["zen-browser-bin"]
        self.assertEqual(p.fix, "my-own-fix")

    def test_repo_package_has_no_command(self):
        self.assertIsNone(self.problems()["somelib"].fix)

    def test_update_check_command_quotes_the_name(self):
        self.assertIn("p='weird;name-bin'", uc.newer_version_cmd("weird;name-bin"))


class ShellCommands(unittest.TestCase):
    """What a script runs, without mistaking text, comments or variables for commands."""

    def test_ignores_quotes_comments_heredocs_and_arithmetic(self):
        script = (
            "#!/bin/bash\n"
            "# grep this comment for nothing\n"
            "set -e\n"
            "echo \"it's done; nothing to see | here\"\n"
            "x=$(( a + b ))\n"
            "notes='one\n"
            "two lines; the end'\n"
            "cat <<END\n"
            "heredoc words; not commands\n"
            "END\n"
            "rfkill list | grep -q blocked && notify-send \"Airplane mode\"\n"
        )
        self.assertEqual(sorted(uc.shell_commands(script)), ["cat", "grep", "notify-send", "rfkill"])

    def test_command_substitution_inside_double_quotes(self):
        script = "v=\"$(pacman -Q linux | awk '{print $2}')\"\n"
        self.assertEqual(sorted(uc.shell_commands(script)), ["awk", "pacman"])

    def test_skips_functions_case_patterns_assignments_and_optional_tools(self):
        script = (
            "step() { printf '%s' \"$1\"; }\n"
            "step \"Building\"\n"
            "LC_ALL=C sudo -u nobody timeout 5 makepkg -s\n"
            "command -v yay >/dev/null && yay -Qua\n"
            "case \"$1\" in\n"
            "    --check|-c) check_all ;;\n"
            "esac\n"
        )
        self.assertEqual(sorted(uc.shell_commands(script)), ["check_all", "makepkg"])

    def test_array_values_are_not_commands(self):
        script = (
            "dirs=(/org/gnome/desktop/interface/ /etc/sddm.conf.d)\n"
            "list+=(foo bar)\n"
            "files=$(ls /tmp)\n"
        )
        self.assertEqual(sorted(uc.shell_commands(script)), ["ls"])

    def test_paths_are_commands_too(self):
        self.assertEqual(list(uc.shell_commands("~/.local/bin/power-mode &")), ["~/.local/bin/power-mode"])

    def test_python_subprocess_calls(self):
        text = ('run(["pacman", "-Q"])\n'
                'if shutil.which("yay"):\n'
                '    run(["yay", "-Qua"])\n'
                'subprocess.call([str(x)])\n')
        self.assertEqual(uc.py_commands(text), {"pacman": 1})


class HyprlandLua(unittest.TestCase):
    CONFIG = (
        'local terminal = "kitty"\n'
        'local shell    = "caelestia shell "   -- talks to the shell\n'
        'hl.exec_cmd("awww-daemon")                        -- wallpaper\n'
        "hl.exec_cmd(\"sh -c 'sleep 1; waypaper --restore'\")\n"
        '-- hl.exec_cmd("old-thing")\n'
        'hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))\n'
        'hl.bind(mod .. " + Space",  hl.dsp.exec_cmd(shell .. "drawers toggle launcher"))\n'
        'hl.exec_cmd("hyprctl plugin load " .. barsPath .. " && hyprctl reload")\n'
        'hl.bind("Print", hl.dsp.exec_cmd("~/.local/bin/screenshot-area"), { locked = true })\n'
        'kb_file = "/home/me/.config/hypr/keymap.xkb",  -- "/not/this/one"\n'
        'local bars = first({ "/usr/lib/a.so", "/usr/lib/b.so" })\n'
    )

    def test_exec_commands_with_variables_filled_in(self):
        cmds = [c for _, c in uc.lua_exec_commands(self.CONFIG)]
        self.assertEqual(cmds[:4], ["awww-daemon", "sh -c 'sleep 1; waypaper --restore'", "kitty",
                                    "caelestia shell drawers toggle launcher"])
        self.assertNotIn("old-thing", " ".join(cmds))  # commented out
        self.assertIn(uc.LUA_UNKNOWN, cmds[4])           # barsPath is only known at runtime
        self.assertEqual(cmds[5], "~/.local/bin/screenshot-area")

    def test_line_numbers(self):
        self.assertEqual(uc.lua_exec_commands(self.CONFIG)[0][0], 3)

    def test_path_literals_skip_comments_and_exec(self):
        self.assertEqual(uc.lua_path_literals(self.CONFIG),
                         [(10, "/home/me/.config/hypr/keymap.xkb"), (11, "/usr/lib/a.so"), (11, "/usr/lib/b.so")])

    def test_missing_commands_look_inside_sh_c(self):
        with mock.patch.object(uc, "command_exists", lambda c: c != "waypaper"):
            self.assertEqual(uc.missing_commands("sh -c 'sleep 1; waypaper --restore'"), ["waypaper"])

    def test_runtime_values_are_never_reported(self):
        with mock.patch.object(uc, "command_exists", lambda c: False):
            cmd = f"test -f  {uc.LUA_UNKNOWN}  && hyprctl plugin load  {uc.LUA_UNKNOWN} "
            self.assertEqual(uc.missing_commands(cmd), ["hyprctl"])  # test is a shell builtin


class FixRunner(unittest.TestCase):
    """--fix runs each fix once, follow-ups once after everything (only if their fix worked), then re-checks."""

    def setUp(self):
        self.ran = []
        self.fail = set()

    def execute(self, cmd, headless):
        self.ran.append(cmd)
        return (1 if cmd in self.fail else 0), ""

    def fixes(self, problems, **kw):
        with mock.patch.object(uc, "execute", self.execute):
            return uc.run_fixes(problems, say=lambda *a: None, **kw)

    def test_follow_ups_run_once_after_all_fixes(self):
        qs = uc.Problem("Quickshell too old", "arch-update --build-local quickshell-pinned", then=("caelestia-patch",))
        cs = uc.Problem("Caelestia too old", "arch-update --build-local caelestia-shell-topbar", then=("caelestia-patch",))
        self.fixes([qs, cs])
        self.assertEqual(self.ran, [qs.fix, cs.fix, "caelestia-patch"])

    def test_no_follow_up_when_the_fix_failed(self):
        self.fail.add("rebuild")
        final, _ = self.fixes([uc.Problem("x", "rebuild", then=("caelestia-patch",))])
        self.assertEqual(self.ran, ["rebuild"])
        self.assertTrue(final[0][1].startswith("the fix failed"))

    def test_re_check_decides_fixed_or_still_broken(self):
        final, _ = self.fixes([uc.Problem("a", "fix-a", verify=lambda: True),
                               uc.Problem("b", "fix-b", verify=lambda: False),
                               uc.Problem("c", "fix-c")])
        self.assertEqual([o for _, o in final], ["fixed", "STILL BROKEN after the fix", "done"])

    def test_ask_mode_skips_what_you_decline(self):
        with mock.patch.object(uc, "confirm", lambda prompt: False):
            final, _ = self.fixes([uc.Problem("a", "fix-a")], ask=True)
        self.assertEqual((self.ran, final[0][1]), ([], "skipped"))

    def test_never_reboots(self):
        final, left = self.fixes([uc.Problem("Reboot needed", uc.REBOOT), uc.Problem("no fix")])
        self.assertEqual((self.ran, final, left), ([], [], []))

    def test_background_leaves_password_fixes_for_a_terminal(self):
        user = uc.Problem("user service failed", "systemctl --user restart foo.service")
        root = uc.Problem("service failed", "sudo systemctl restart bar.service")
        build = uc.Problem("old build", "arch-update --build-local x", then=("caelestia-patch",))
        _, left = self.fixes([user, root, build], headless=True)
        self.assertEqual(self.ran, [user.fix])
        self.assertEqual(left, [root, build])

    def test_needs_terminal(self):
        for cmd in ("sudo pacman -S x", "sudo DIFFPROG='nvim -d' pacdiff", "arch-update --build-hymission", "yay -S --rebuild x"):
            self.assertTrue(uc.needs_terminal(cmd), cmd)
        for cmd in ("caelestia-patch", "systemctl --user restart a.service", uc.newer_version_cmd("zen-browser-bin"), uc.start_shell_cmd("caelestia"), uc.start_shell_cmd("rice")):
            self.assertFalse(uc.needs_terminal(cmd), cmd)

    def test_one_entry_per_fix(self):
        merged = uc.one_per_fix([uc.Problem("Quickshell built before Qt 6.12", "rebuild-qs"),
                                 uc.Problem("no fix"), uc.Problem("Quickshell doesn't match Qt", "rebuild-qs")])
        self.assertEqual(len(merged), 2)
        self.assertIn("Also: Quickshell doesn't match Qt", merged[0].what)


class CaelestiaCopy(unittest.TestCase):
    """The patched copy must be exactly: installed Caelestia + your patches."""

    PATCH = (
        "--- a/shell.qml\n"
        "+++ b/shell.qml\n"
        "@@ -1,2 +1,2 @@\n"
        " import QtQuick\n"
        "-Bar { position: \"bottom\" }\n"
        "+Bar { position: \"top\" }\n"
    )

    def setUp(self):
        tmp = self.enterContext(tempfile.TemporaryDirectory())
        self.src, self.copy, self.patches = (Path(tmp, d) for d in ("src", "copy", "patches"))
        for d in (self.src, self.copy, self.patches):
            d.mkdir()
        (self.src / "shell.qml").write_text('import QtQuick\nBar { position: "bottom" }\n')
        (self.src / "Other.qml").write_text("Item {}\n")
        (self.patches / "top.patch").write_text(self.PATCH)
        (self.copy / "shell.qml").write_text('import QtQuick\nBar { position: "top" }\n')
        (self.copy / "Other.qml").write_text("Item {}\n")
        for name, path in (("CAELESTIA_SRC", self.src), ("CAELESTIA_COPY", self.copy), ("CAELESTIA_PATCHES", self.patches)):
            self.enterContext(mock.patch.object(uc, name, path))

    def problems(self):
        return [p.what for p in uc.caelestia_copy_problems()[0]]

    def test_up_to_date(self):
        self.assertEqual(self.problems(), [])

    def test_package_changed_an_unpatched_file(self):
        (self.src / "Other.qml").write_text("Item { visible: true }\n")
        self.assertIn("Other.qml", self.problems()[0])

    def test_patch_not_applied(self):
        (self.copy / "shell.qml").write_text('import QtQuick\nBar { position: "bottom" }\n')
        self.assertIn("shell.qml", self.problems()[0])

    def test_file_missing_from_copy(self):
        (self.copy / "Other.qml").unlink()
        self.assertIn("Other.qml", self.problems()[0])

    def test_patch_no_longer_applies(self):
        (self.src / "shell.qml").write_text('import QtQuick\nBar { anchors.top: true }\n')
        found = uc.caelestia_copy_problems()[0]
        self.assertIn("top.patch no longer apply", found[0].what)
        self.assertIsNone(found[0].fix)  # caelestia-patch can't fix that; it needs redoing by hand

    def test_patched_files(self):
        self.assertEqual(uc.patched_files(self.PATCH + "--- /dev/null\n+++ b/modules/New.qml\n"),
                         ["shell.qml", "modules/New.qml"])

class TerminalHandOff(unittest.TestCase):
    """Fixes that need a password go to a terminal: now, or once nothing is fullscreen (not behind a game)."""

    def hand_off(self, is_fullscreen):
        opened, spawned = [], []
        sudo = uc.Problem("service failed", "sudo systemctl restart bar.service")
        with mock.patch.object(uc, "run_fixes", lambda problems, **kw: ([], [sudo])), \
             mock.patch.object(uc, "fullscreen", lambda: is_fullscreen), \
             mock.patch.object(uc, "open_fix_terminal", lambda: opened.append(True)), \
             mock.patch.object(uc.subprocess, "Popen", lambda cmd, **kw: spawned.append(cmd)):
            outcomes, left, _ = uc.auto_fix([sudo])
        return opened, spawned, outcomes[id(sudo)]

    def test_opens_a_terminal_straight_away(self):
        opened, spawned, outcome = self.hand_off(False)
        self.assertEqual((opened, spawned), ([True], []))
        self.assertIn("a terminal opened", outcome)

    def test_waits_while_something_is_fullscreen(self):
        opened, spawned, outcome = self.hand_off(True)
        self.assertEqual(opened, [])
        self.assertEqual(spawned[0][1:], ["--fix-later"])
        self.assertIn("once you leave fullscreen", outcome)

if __name__ == "__main__":
    unittest.main()
