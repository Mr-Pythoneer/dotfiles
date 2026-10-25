"""Tests for the adaptive parts: what counts as your files, the history, why-it-broke, and the
discovery checks (shells, Hyprland's config check, Python imports, launchers).

Run: python3 -m unittest discover -s tests   (from the repo directory)
"""
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
import smart  # noqa: E402

_loader = importlib.machinery.SourceFileLoader("update_check", str(REPO / "update-check"))
_spec = importlib.util.spec_from_loader("update_check", _loader)
uc = importlib.util.module_from_spec(_spec)
_loader.exec_module(uc)

EDT = timezone(timedelta(hours=-4))


class TempHome(unittest.TestCase):
    """Point smart at a throwaway home folder."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        state = self.home / ".local/state/update-check"
        self.patches = [mock.patch.multiple(smart, HOME=self.home, STATE=state, GIT_DIR=state / "history.git",
                                            RUNS=state / "runs", LESSONS=state / "lessons.md",
                                            ATTEMPTS=state / "ai-attempts.json", UNDONE=state / "undone")]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def put(self, rel, text="x\n", data=None):
        f = self.home / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        if data is not None:
            f.write_bytes(data)
        else:
            f.write_text(text)
        return f


class TrackedFiles(TempHome):
    def test_keeps_configs_and_scripts_skips_profiles_secrets_and_junk(self):
        keep = [self.put(".config/hypr/hyprland.lua"), self.put(".config/newapp/settings.toml"),
                self.put(".config/top-level.conf"), self.put(".local/bin/myscript", "#!/bin/sh\n"),
                self.put(".local/share/applications/thing.desktop")]
        skip = [self.put(".config/SomeElectron/Local Storage/leveldb/000.log"), self.put(".config/SomeElectron/settings.json"),
                self.put(".config/google-chrome/Default/Cookies"), self.put(".config/google-chrome/Default/Preferences"),
                self.put(".config/thunderbird/abc.default-release/prefs.js"),
                self.put(".config/thunderbird/abc.default-release/logins.json"),
                self.put(".config/gh/hosts.yml"), self.put(".config/app/api-token"), self.put(".config/app/secrets.env"),
                self.put(".config/app/big.json", "x" * (smart.MAX_FILE + 1)), self.put(".config/app/blob.bin", data=b"\0\1\2"),
                self.put(".config/app/node_modules/pkg/index.js"), self.put(".local/share/other/data.txt")]
        found = set(smart.tracked_files())
        for f in keep:
            self.assertIn(f, found, f)
        for f in skip:
            self.assertNotIn(f, found, f)

    def test_big_folders_are_left_out(self):
        with mock.patch.object(smart, "MAX_DIR", 10):
            self.put(".config/huge/a.txt", "0123456789abc")
            self.put(".config/small/a.txt", "ok")
            found = {f.relative_to(self.home).parts[1] for f in smart.tracked_files()}
        self.assertNotIn("huge", found)
        self.assertIn("small", found)


@unittest.skipUnless(smart.shutil.which("git"), "needs git")
class History(TempHome):
    def test_snapshot_changes_and_restore(self):
        f = self.put(".config/app/a.conf", "one\n")
        self.put(".config/app/b.conf", "b\n")
        smart.mark_good()
        f.write_text("two\n")
        self.put(".config/app/new.conf", "new\n")
        (self.home / ".config/app/b.conf").unlink()
        smart.snapshot("later")
        changed = dict((p, st) for st, p in smart.changed_since())
        self.assertEqual(changed, {".config/app/a.conf": "M", ".config/app/new.conf": "A", ".config/app/b.conf": "D"})
        self.assertIn("later", smart.history_log(".config/app/a.conf"))
        self.assertEqual(smart.history_show("good", ".config/app/a.conf"), "one\n")

    def test_no_commit_when_nothing_changed(self):
        self.put(".config/app/a.conf")
        first = smart.snapshot("one")
        self.assertEqual(smart.snapshot("two"), first)

    def test_files_that_stop_counting_are_dropped(self):
        f = self.put(".config/app/a.conf", "small\n")
        smart.snapshot("one")
        f.write_text("x" * (smart.MAX_FILE + 1))
        smart.snapshot("two")
        _, out = smart.git("ls-files")
        self.assertNotIn(".config/app/a.conf", out)

    def test_undo_puts_back_and_spares_later_edits(self):
        a, b = self.put(".config/app/a.conf", "a1\n"), self.put(".config/app/b.conf", "b1\n")
        smart.snapshot("before", tag="pre/r1")
        a.write_text("a2\n")
        b.write_text("b2\n")
        made = self.put(".config/app/made.conf", "new\n")
        smart.snapshot("fix", tag="fix/r1")
        b.write_text("b3 (yours)\n")
        run_id, done = smart.undo("r1")
        self.assertEqual(run_id, "r1")
        self.assertEqual(a.read_text(), "a1\n")
        self.assertEqual(b.read_text(), "b3 (yours)\n")
        self.assertFalse(made.exists())
        self.assertTrue((smart.UNDONE / "r1/.config/app/made.conf").exists())
        self.assertTrue(any("left alone" in d for d in done))


class Explain(unittest.TestCase):
    def change(self, name, old="1", new="2", action="upgraded", day=10):
        return uc.Change(datetime(2026, 10, day, 12, tzinfo=EDT), action, name, old, new)

    def test_your_edit(self):
        why = smart.explain("hyprland.lua:12 starts `foo`, which isn't installed.", [],
                            [("M", ".config/hypr/hyprland.lua")])
        self.assertIn("you edited ~/.config/hypr/hyprland.lua", why)

    def test_package_named_in_the_problem(self):
        why = smart.explain("Quickshell (quickshell-pinned) was built for a different Qt",
                            [self.change("quickshell-pinned", "0.3.1-1", "0.3.1-2"), self.change("zlib")], [])
        self.assertIn("quickshell-pinned went from 0.3.1-1 to 0.3.1-2", why)
        self.assertNotIn("zlib", why)

    def test_falls_back_to_key_packages(self):
        why = smart.explain("The bar logged that part of it failed to load", [self.change("qt6-base", "6.12.0", "6.12.1"),
                                                                             self.change("zlib")], [])
        self.assertIn("most likely the update", why)
        self.assertIn("qt6-base", why)

    def test_only_changes_since_the_good_check(self):
        good = datetime(2026, 10, 12, tzinfo=EDT)
        why = smart.explain("qt6-base thing", [self.change("qt6-base", day=10)], [], good)
        self.assertIsNone(why)

    def test_nothing_known(self):
        self.assertIsNone(smart.explain("something odd", [self.change("zlib")], []))


class Answers(unittest.TestCase):
    def test_structured_output(self):
        out = json.dumps({"structured_output": {"fixes": [{"problem": "p", "cause": "c", "did": "d", "files": [], "fixed": True}]},
                          "total_cost_usd": 0.1})
        ans, raw = smart.parse_answer(out)
        self.assertEqual(ans["fixes"][0]["did"], "d")
        self.assertEqual(ans["needs_you"], [])

    def test_errors_and_garbage(self):
        self.assertIsNone(smart.parse_answer('{"is_error": true, "result": "nope"}')[0])
        self.assertIsNone(smart.parse_answer("not json")[0])

    def test_retry_only_after_an_update_or_a_week(self):
        now = datetime.now(timezone.utc)
        attempts = {smart._key("Problem 12 in x"): now.timestamp()}
        self.assertFalse(smart.worth_trying("Problem 13 in x", attempts, now - timedelta(days=1)))
        self.assertTrue(smart.worth_trying("Problem 13 in x", attempts, now + timedelta(minutes=1)))
        self.assertTrue(smart.worth_trying("something else", attempts, None))

    def test_off_unless_turned_on(self):
        self.assertFalse(smart.ai_settings({})["enabled"])
        self.assertTrue(smart.ai_settings({"ai": {"enabled": True}})["enabled"])


class DiscoveryChecks(unittest.TestCase):
    def test_start_command_never_makes_a_second_copy(self):
        self.assertIn("qs -c rice -n -d", uc.start_shell_cmd("rice", "qs -c rice -d"))
        self.assertIn("caelestia shell -d", uc.start_shell_cmd("caelestia"))
        self.assertEqual(uc.start_shell_cmd("x", "qs -c x -n -d").count("-n"), 1)
        self.assertTrue(uc.start_shell_cmd("rice").startswith("hyprctl eval"))

    def test_shell_log_errors_ignore_noise(self):
        log = ("\x1b[33m  WARN\x1b[0m scene: @modules/bar/BarWrapper.qml[26:-1]: TypeError: Cannot read property 'width' of null\n"
               "  WARN: Could not load icon \"x\"\n"
               "  ERROR: qml: file:///a/Bar.qml:5:1: Battery is not a type\n"
               "  ERROR: qml: file:///a/Bar.qml:5:1: Battery is not a type\n"
               '  WARN: module "Quickshell.Services.Foo" is not installed\n')
        with mock.patch.object(uc, "run", return_value=(0, log, "")):
            errors = uc.shell_log_errors(1)
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("is not a type" in e for e in errors))

    def test_hyprland_config_errors(self):
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "x"}), \
                mock.patch.object(uc, "run", return_value=(0, json.dumps(["", "hyprland.lua:3: unknown option foo"]), "")):
            probs, n = uc.hypr_config_problems()
        self.assertEqual(len(probs), 1)
        self.assertIn("unknown option foo", probs[0].what)
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "x"}), \
                mock.patch.object(uc, "run", return_value=(0, '[""]', "")):
            self.assertEqual(uc.hypr_config_problems()[0], [])

    def test_python_imports_skip_optional_ones(self):
        mods = uc.python_imports("import os, json.decoder\nfrom pathlib import Path\nfrom . import local\n"
                                 "try:\n    import yaml\nexcept ImportError:\n    yaml = None\n"
                                 "def f():\n    import requests\n")
        self.assertEqual(set(mods), {"os", "json", "pathlib", "requests"})

    def test_python_import_problem(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "tool").write_text("#!/usr/bin/env python3\nimport os\nimport definitely_not_a_module_xyz\n")
            Path(d, "tool").chmod(0o755)
            with mock.patch.object(uc, "BIN", Path(d)):
                probs, n = uc.python_import_problems()
        self.assertEqual(n, 1)
        self.assertEqual(len(probs), 1)
        self.assertIn("definitely_not_a_module_xyz", probs[0].what)

    def test_desktop_entries(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            apps, auto = home / ".local/share/applications", home / ".config/autostart"
            apps.mkdir(parents=True)
            auto.mkdir(parents=True)
            (apps / "ok.desktop").write_text("[Desktop Entry]\nExec=env FOO=1 sh -c true %U\n")
            (apps / "gone.desktop").write_text("[Desktop Entry]\nExec=/nonexistent/app --flag\n")
            (auto / "hidden.desktop").write_text("[Desktop Entry]\nExec=nonexistent-thing\nHidden=true\n")
            (auto / "action.desktop").write_text("[Desktop Entry]\nExec=sh\n[Desktop Action x]\nExec=nonexistent-thing\n")
            with mock.patch.object(uc, "HOME", home):
                probs, n = uc.desktop_entry_problems()
        self.assertEqual(n, 3)
        self.assertEqual([p.what.split(" ")[0] for p in probs], ["gone.desktop"])

    def test_autostarted_shells(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            for name in ("caelestia", "rice"):
                (home / ".config/quickshell" / name).mkdir(parents=True)
                (home / ".config/quickshell" / name / "shell.qml").write_text("")
            lua = home / "hyprland.lua"
            lua.write_text('hl.exec_cmd("caelestia shell -d")\nhl.exec_cmd("qs -c rice -d")\n'
                           'hl.bind("SUPER + D", hl.dsp.exec_cmd("qs -c rice ipc call panels toggle dashboard"))\n'
                           'hl.exec_cmd("qs -c missing -d")\n')
            with mock.patch.object(uc, "QS_CONFIGS", home / ".config/quickshell"), \
                    mock.patch.object(uc, "lua_config_files", return_value=([lua], [])):
                shells = uc.autostarted_shells()
        self.assertEqual(sorted(shells), ["caelestia", "rice"])

    def test_problems_know_why_and_news_is_not_repairable(self):
        p = uc.Problem("x")
        self.assertIsNone(p.cause)
        self.assertTrue(p.repairable)
        lines = uc.render_problems([p._replace(cause="you edited ~/a")])
        self.assertIn("      why: you edited ~/a", lines)


class ClaudeRepairFlow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.runs = mock.patch.object(smart, "RUNS", Path(self.tmp.name))
        self.runs.start()
        Path(self.tmp.name).mkdir(exist_ok=True)

    def tearDown(self):
        self.runs.stop()
        self.tmp.cleanup()

    def test_what_goes_to_claude(self):
        no_fix = uc.Problem("launcher runs foo, which isn't installed")
        failed = uc.Problem("service failed", "systemctl --user restart x")
        worked = uc.Problem("shell not running", "start it")
        reboot = uc.Problem("Reboot needed", uc.REBOOT)
        news = uc.Problem("Official Caelestia now has the top bar", repairable=False)
        waiting = uc.Problem("needs sudo", "sudo thing")
        final = [(failed, "the fix failed (exit code 1)"), (worked, "fixed")]
        todo = uc.repairable_left([no_fix, failed, worked, reboot, news, waiting], final, [waiting])
        self.assertEqual([t["what"] for t in todo], [no_fix.what, failed.what])
        self.assertEqual(todo[1]["tried"], failed.fix)

    def fake_run(self, problems):
        return {"id": "r1", "time": datetime.now().isoformat(), "problems": problems, "files_changed": [".config/x"],
                "fixes": [{"problem": problems[0] + " (reworded)", "cause": "typo", "did": "fixed the typo",
                           "files": ["~/.config/x"], "fixed": True}],
                "needs_you": [], "error": None}

    def test_verified_only_when_the_recheck_agrees(self):
        p = uc.Problem("zz.desktop runs kittyy, which isn't installed.")
        with mock.patch.object(uc.smart, "ai_fix", side_effect=lambda todo, *a, **k: (self.fake_run([t["what"] for t in todo]), "")), \
                mock.patch.object(uc, "read_pacman_log", return_value=([], [])), \
                mock.patch.object(uc.smart, "tag_time", return_value=None), \
                mock.patch.object(uc.smart, "changed_since", return_value=[]), \
                mock.patch.object(uc, "load_config", return_value=({}, None)):
            with mock.patch.object(uc, "after_update", return_value=([], [], [], None, "")):
                run_, _, _ = uc.claude_repair([p], [], [], say=lambda *a: None)
            self.assertTrue(run_["fixes"][0]["verified"])
            self.assertEqual(run_["fixes"][0]["about"], p.what)
            with mock.patch.object(uc, "after_update", return_value=([], [p], [], None, "")):
                run_, _, _ = uc.claude_repair([p], [], [], say=lambda *a: None)
            self.assertFalse(run_["fixes"][0]["verified"])

    def test_background_reports_claudes_fix(self):
        p = uc.Problem("zz.desktop runs kittyy, which isn't installed.")
        run_ = self.fake_run([p.what])
        run_["fixes"][0].update(about=p.what, verified=True)
        with mock.patch.object(uc, "run_fixes", return_value=([], [])), \
                mock.patch.object(uc, "claude_repair", return_value=(run_, "", [])), \
                mock.patch.object(uc, "fullscreen", return_value=False), \
                mock.patch.object(uc, "open_fix_terminal") as term:
            outcomes, left, got = uc.auto_fix([p])
        self.assertTrue(outcomes[id(p)].startswith("fixed by Claude: fixed the typo"))
        self.assertEqual(left, [])
        term.assert_not_called()
        self.assertIs(got, run_)

    def test_needs_you_goes_to_the_terminal(self):
        p = uc.Problem("module foo missing")
        run_ = {"id": "r2", "fixes": [], "files_changed": [], "error": None, "problems": [p.what],
                "needs_you": [{"problem": p.what, "about": p.what, "cause": "pip module gone", "command": "sudo pacman -S python-foo", "why": "installs it"}]}
        with mock.patch.object(uc, "run_fixes", return_value=([], [])), \
                mock.patch.object(uc, "claude_repair", return_value=(run_, "", [])), \
                mock.patch.object(uc, "fullscreen", return_value=False), \
                mock.patch.object(uc, "open_fix_terminal") as term:
            outcomes, left, _ = uc.auto_fix([p])
        self.assertEqual(left, [p])
        term.assert_called_once()

    def test_report_says_why_what_and_how_to_undo(self):
        run_ = self.fake_run(["p"])
        run_["fixes"][0].update(about="p", verified=True)
        text = "\n".join(uc.render_repair(run_))
        self.assertIn("why it broke: typo", text)
        self.assertIn("what was done: fixed the typo", text)
        self.assertIn("re-check confirms", text)
        self.assertIn("update-check --undo r1", text)


class Waiter(unittest.TestCase):
    def test_newest_notification_retires_the_old_waiter(self):
        import subprocess
        import time
        old = subprocess.Popen(["sh", "-c", "sleep 30", "update-check"])
        with tempfile.TemporaryDirectory() as d:
            waiter = Path(d, "waiter.pid")
            waiter.write_text(str(old.pid))
            with mock.patch.multiple(uc, CACHE=Path(d), WAITER=waiter):
                uc.replace_waiter()
                self.assertEqual(waiter.read_text(), str(os.getpid()))
        for _ in range(50):
            if old.poll() is not None:
                break
            time.sleep(0.1)
        self.assertIsNotNone(old.poll(), "the old waiter should have been ended")

    def test_leaves_unrelated_processes_alone(self):
        import subprocess
        other = subprocess.Popen(["sleep", "30"])
        try:
            with tempfile.TemporaryDirectory() as d:
                waiter = Path(d, "waiter.pid")
                waiter.write_text(str(other.pid))
                with mock.patch.multiple(uc, CACHE=Path(d), WAITER=waiter):
                    uc.replace_waiter()
            self.assertIsNone(other.poll())
        finally:
            other.kill()
            other.wait()


if __name__ == "__main__":
    unittest.main()
