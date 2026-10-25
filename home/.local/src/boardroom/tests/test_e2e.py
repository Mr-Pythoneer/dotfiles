"""A whole company run against the mock API: the CEO (Anthropic API) delegates to two workers
(OpenAI-compatible API), one worker spawns subagents, then the debugger checks the result."""

import os
import re
import tempfile
import unittest
from pathlib import Path

os.environ["BOARDROOM_HOME"] = tempfile.mkdtemp(prefix="boardroom-test-home-")

from boardroom import config  # noqa: E402
from boardroom.company import Company  # noqa: E402
from boardroom.events import Bus  # noqa: E402
from tests.mock_api import MockAPI  # noqa: E402


def script(system, task, step, last):
    who = re.search(r"You are (?:the CEO|([\w.-]+), )", system)
    me = "ceo" if "You are the CEO" in system else who.group(1)
    if me == "ceo":
        if step == 0:
            return "tool", "delegate", {"assignments": [
                {"to": "worker-1", "task": "Write a.txt containing A"},
                {"to": "any", "task": "Write b.txt containing B, using subagents for b1 and b2"}]}
        if step == 1:
            assert "worker-1: done" in last and "worker-2: done" in last, last
            return "tool", "delegate", {"assignments": [
                {"to": "debugger", "task": "Check a.txt, b.txt, b1.txt and b2.txt"}]}
        assert "VERIFIED" in last, last
        return "text", "All done: a.txt, b.txt, b1.txt, b2.txt exist and were checked."
    if me == "worker-1":
        if step == 0:
            return "tool", "write_file", {"path": "a.txt", "content": "A"}
        return "text", "wrote a.txt"
    if me == "worker-2":
        if step == 0:
            return "tool", "spawn_subagents", {"tasks": ["write b1.txt", "write b2.txt"]}
        if step == 1:
            assert "worker-2.sub1: done" in last and "worker-2.sub2: done" in last, last
            return "tool", "write_file", {"path": "b.txt", "content": "B"}
        return "text", "wrote b.txt; subagents wrote b1.txt and b2.txt"
    if me.startswith("worker-2.sub"):
        name = re.search(r"b\d\.txt", task).group(0)
        if step == 0:
            return "tool", "write_file", {"path": name, "content": name}
        return "text", f"wrote {name}"
    if me == "debugger":
        if step == 0:
            return "tool", "run_shell", {"command": "cat a.txt b.txt b1.txt b2.txt"}
        ok = "AB" in last.replace("\n", "") and "b1.txt" in last
        return "text", "VERIFIED" if ok else f"BROKEN: {last}"
    raise AssertionError(f"unexpected agent {me}")


class CompanyRun(unittest.TestCase):
    def setUp(self):
        self.api = MockAPI(script)
        self.ws = Path(tempfile.mkdtemp(prefix="boardroom-test-ws-"))
        self.accounts = {
            "anth": {"kind": "anthropic", "base_url": self.api.url, "key": "x",
                     "models": ["mock-opus"]},
            "oai": {"kind": "openai-compat", "base_url": self.api.url + "/v1", "key": "x",
                    "models": ["mock-sonnet"]},
        }
        self.settings = {**config.DEFAULT_SETTINGS, "roles": {}, "models": {}, "member": [
            {"id": "ceo", "role": "ceo", "model": "anth:mock-opus"},
            {"id": "debugger", "role": "debugger", "model": "oai:mock-sonnet"},
            {"id": "worker-1", "role": "worker", "model": "oai:mock-sonnet"},
            {"id": "worker-2", "role": "worker", "model": "oai:mock-sonnet"},
        ]}

    def tearDown(self):
        self.api.close()

    def test_full_company(self):
        events = []
        bus = Bus(self.ws / "events.jsonl")
        bus.subscribe(events.append)
        company = Company(self.settings, self.accounts, self.ws, bus)
        try:
            res = company.run("Make four files")
        finally:
            company.close()
            bus.close()
        self.assertTrue(res.ok, res.text)
        self.assertIn("All done", res.text)
        for name, content in [("a.txt", "A"), ("b.txt", "B"), ("b1.txt", "b1.txt"), ("b2.txt", "b2.txt")]:
            self.assertEqual((self.ws / name).read_text(), content)
        kinds = [(e["type"], e["agent"], e.get("to")) for e in events]
        self.assertIn(("delegate", "ceo", "worker-1"), kinds)
        self.assertIn(("delegate", "ceo", "worker-2"), kinds)
        self.assertIn(("delegate", "ceo", "debugger"), kinds)
        self.assertIn(("spawn", "worker-2", "worker-2.sub1"), kinds)
        self.assertIn(("report", "worker-2.sub2", "worker-2"), kinds)
        self.assertEqual(set(company.usage), {"ceo", "worker-1", "worker-2", "debugger"})
        self.assertEqual(company.usage["ceo"]["input"], 300)   # three CEO calls, 100 each
        self.assertTrue((self.ws / "events.jsonl").stat().st_size > 0)
        # the Anthropic requests cache the system prompt and the newest message
        anth = [b for p, b in self.api.calls if p == "/v1/messages"]
        self.assertIn("cache_control", anth[-1]["system"][0])
        self.assertEqual(anth[-1]["cache_control"], {"type": "ephemeral"})   # top-level caching

    def test_outside_paths_refused(self):
        def evil(system, task, step, last):
            if step == 0:
                return "tool", "write_file", {"path": "../escape.txt", "content": "x"}
            return "text", last
        api = MockAPI(evil)
        try:
            accounts = {"oai": {"kind": "openai-compat", "base_url": api.url + "/v1", "key": "x",
                                "models": ["m"]}}
            settings = {**self.settings, "member": [{"id": "ceo", "role": "ceo", "model": "oai:m"}]}
            company = Company(settings, accounts, self.ws, Bus())
            res = company.run("escape")
            company.close()
        finally:
            api.close()
        self.assertIn("outside the project folder", res.text)
        self.assertFalse((self.ws.parent / "escape.txt").exists())

    def test_no_shell_has_no_shell_tool(self):
        settings = {**self.settings, "autonomy": "no-shell"}
        company = Company(settings, self.accounts, self.ws, Bus())
        from boardroom.company import Spec
        spec = Spec("worker-1", settings["member"][2], "worker", "oai:mock-sonnet", "ceo")
        names = [t.name for t in company.tools_for(spec)]
        company.close()
        self.assertNotIn("run_shell", names)
        self.assertIn("spawn_subagents", names)
        self.assertNotIn("delegate", names)


if __name__ == "__main__":
    unittest.main()
