"""CLI members: a Claude Code CEO delegates to a Claude Code worker through the bridge and the
MCP server, with a stand-in `claude` program (tests/fake_claude.py)."""

import os
import stat
import tempfile
import threading
import unittest
from pathlib import Path

os.environ.setdefault("BOARDROOM_HOME", tempfile.mkdtemp(prefix="boardroom-test-home-"))

from boardroom import config  # noqa: E402
from boardroom.company import Company  # noqa: E402
from boardroom.connectors.claude_code import ClaudeCodeConnector  # noqa: E402
from boardroom.events import Bus  # noqa: E402

FAKE = Path(__file__).with_name("fake_claude.py")


class ClaudeCodeMembers(unittest.TestCase):
    def setUp(self):
        FAKE.chmod(FAKE.stat().st_mode | stat.S_IXUSR)
        self.ws = Path(tempfile.mkdtemp(prefix="boardroom-test-ws-"))
        # One slot only: the CEO must give its slot back while it waits for the worker,
        # otherwise this test hangs.
        self.accounts = {"claude": {"kind": "claude-code", "command": str(FAKE),
                                    "models": ["opus", "sonnet"], "max_parallel": 1}}
        self.settings = {**config.DEFAULT_SETTINGS, "roles": {}, "models": {}, "member": [
            {"id": "ceo", "role": "ceo", "model": "claude:opus"},
            {"id": "worker-1", "role": "worker", "model": "claude:sonnet"}]}

    def test_delegation_through_mcp(self):
        events = []
        bus = Bus()
        bus.subscribe(events.append)
        company = Company(self.settings, self.accounts, self.ws, bus)
        box = {}
        t = threading.Thread(target=lambda: box.setdefault("r", company.run("make c.txt")))
        t.start()
        t.join(60)
        company.close()
        self.assertFalse(t.is_alive(), "the run hung (slot not released while delegating?)")
        res = box["r"]
        self.assertTrue(res.ok, res.text)
        self.assertEqual((self.ws / "c.txt").read_text(), "C")
        self.assertIn("worker-1: done", res.text)
        self.assertIn("prompt was: write c.txt", res.text)
        self.assertEqual(res.session, "sess-1")
        seen = [(e["type"], e["agent"], e.get("to") or e.get("name")) for e in events]
        self.assertIn(("delegate", "ceo", "worker-1"), seen)
        self.assertIn(("tool", "worker-1", "Write"), seen)
        self.assertIn(("spawn", "worker-1", "worker-1.sub1"), seen)
        self.assertIn(("tool", "worker-1.sub1", "Bash"), seen)     # subagent's own tool use
        self.assertIn(("report", "worker-1.sub1", "worker-1"), seen)
        self.assertIn(("text", "ceo", None), seen)                   # "Planning: ..."
        self.assertEqual(company.usage["worker-1"], {"input": 100, "output": 20, "cost": 0.0})
        tool_ev = next(e for e in events if e["type"] == "tool" and e["name"] == "Write")
        self.assertEqual(tool_ev["summary"], "c.txt")

    def test_connection_test(self):
        ok, msg = ClaudeCodeConnector("claude", self.accounts["claude"]).test()
        self.assertTrue(ok)
        self.assertIn("max plan", msg)

    def test_permission_args(self):
        c = ClaudeCodeConnector("claude", {})
        self.assertIn("mcp__boardroom__approve", c.permission_args("ask"))
        self.assertIn("Bash", c.permission_args("no-shell"))
        full = c.permission_args("full")
        self.assertTrue("bypassPermissions" in full or "--settings" in full)


class GeminiCliMembers(unittest.TestCase):
    def test_delegation_and_subagents_through_mcp(self):
        fake = Path(__file__).with_name("fake_gemini.py")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        ws = Path(tempfile.mkdtemp(prefix="boardroom-test-ws-"))
        accounts = {"google": {"kind": "gemini-cli", "command": str(fake), "billing": "api",
                               "models": ["gemini-pro", "gemini-flash"], "max_parallel": 1}}
        settings = {**config.DEFAULT_SETTINGS, "roles": {}, "models": {}, "member": [
            {"id": "ceo", "role": "ceo", "model": "google:gemini-pro"},
            {"id": "worker-1", "role": "worker", "model": "google:gemini-pro",
             "subagent_model": "google:gemini-flash"}]}
        events = []
        bus = Bus()
        bus.subscribe(events.append)
        company = Company(settings, accounts, ws, bus)
        box = {}
        t = threading.Thread(target=lambda: box.setdefault("r", company.run("make g.txt")))
        t.start()
        t.join(60)
        company.close()
        self.assertFalse(t.is_alive(), "the run hung")
        res = box["r"]
        self.assertTrue(res.ok, res.text)
        self.assertEqual(res.session, "gem-1")
        self.assertEqual((ws / "g.txt").read_text(), "G")
        self.assertEqual((ws / "sub.txt").read_text(), "S")
        self.assertIn("worker-1: done", res.text)
        self.assertIn("sub wrote sub.txt", res.text)
        seen = [(e["type"], e["agent"], e.get("to") or e.get("name")) for e in events]
        self.assertIn(("delegate", "ceo", "worker-1"), seen)
        self.assertIn(("spawn", "worker-1", "worker-1.sub1"), seen)
        self.assertIn(("tool", "worker-1", "write_file"), seen)
        self.assertIn(("tool", "worker-1", "run_shell_command"), seen)
        self.assertIn(("text", "ceo", None), seen)            # "Planning: worker-1 makes g.txt."
        self.assertNotIn("mcp_boardroom_delegate", [e.get("name") for e in events])
        # billing = "api": the cost of the models Gemini reports, from the price table
        self.assertGreater(company.usage["ceo"]["cost"], 0)
        self.assertEqual(company.usage["ceo"]["input"], 100)


if __name__ == "__main__":
    unittest.main()
