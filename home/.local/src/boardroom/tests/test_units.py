import json
import os
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

os.environ.setdefault("BOARDROOM_HOME", tempfile.mkdtemp(prefix="boardroom-test-home-"))

from boardroom import catalog, config, org  # noqa: E402
from boardroom.connectors.anthropic_api import from_anthropic, to_anthropic  # noqa: E402
from boardroom.connectors.base import ToolCall  # noqa: E402
from boardroom.connectors.openai_compat import from_openai, to_openai  # noqa: E402


class Toml(unittest.TestCase):
    def test_round_trip(self):
        data = {
            "name": 'Acme "AI"\nCorp\t\\',
            "autonomy": "full", "max_steps": 80, "budget": 1.5, "on": True,
            "tags": ["a", "b"],
            "accounts": {"claude": {"kind": "claude-code", "models": ["opus", "sonnet"]},
                         "my.local": {"kind": "openai-compat", "env": {"A": "1"}}},
            "models": {"gpt-5.6-luna": {"tier": "frontier", "score": 93}},
            "member": [{"id": "ceo", "role": "ceo", "model": "claude:opus"},
                       {"id": "worker-1", "role": "worker", "model": "claude:sonnet"}],
        }
        self.assertEqual(tomllib.loads(config.dumps(data)), data)


class Catalog(unittest.TestCase):
    def tier(self, name):
        return catalog.classify(name).tier

    def test_tiers(self):
        cases = {
            "opus": "frontier", "claude-opus-5-5": "frontier", "sonnet": "strong",
            "claude-sonnet-5-5": "strong", "haiku": "fast", "claude-haiku-5-5": "fast",
            "gpt-6.1-sol": "frontier", "gpt-5.6-luna": "fast", "gpt-5.5-pro": "frontier",
            "gpt-6-astra": "frontier", "gpt-5.6-terra": "strong", "gpt-6-luna": "fast",
            "deepseek-v4-pro": "strong", "deepseek-flash": "fast", "gpt-oss-120b": "strong",
            "gpt-5.6-mini": "fast", "gpt-5-nano": "fast", "gpt-4.1": "strong", "o3": "strong",
            "o4-mini": "fast", "deepseek-chat": "strong", "deepseek-reasoner": "strong",
            "gemini-2.5-pro": "frontier", "gemini-2.5-flash": "fast",
            "gemini-2.5-flash-lite": "fast", "llama3.1:8b": "fast",
            "meta-llama/llama-3.3-70b-instruct": "strong", "something-new": "strong",
            "anthropic/claude-sonnet-5": "strong", "gpt-5.1-codex-mini": "fast",
            "gpt-5.1-codex": "frontier", "gpt-6-luna-mini": "fast", "o3-pro": "frontier",
        }
        for name, tier in cases.items():
            self.assertEqual(self.tier(name), tier, name)

    def test_order(self):
        s = lambda n: catalog.classify(n).score  # noqa: E731
        self.assertGreater(s("claude-opus-5-5"), s("claude-opus-4-1"))
        self.assertGreater(s("opus"), s("claude-opus-5-5"))       # alias = newest
        self.assertGreater(s("gpt-6.1-sol"), s("gpt-5.5"))
        self.assertGreater(s("claude-opus-4-1-20250805"), s("claude-opus-4"))  # date ignored

    def test_families(self):
        self.assertEqual(catalog.family_of("anthropic/claude-sonnet-5"), "anthropic")
        self.assertEqual(catalog.family_of("gpt-6-luna"), "openai")
        self.assertEqual(catalog.family_of("o3"), "openai")
        self.assertEqual(catalog.family_of("deepseek-chat"), "deepseek")

    def test_override(self):
        info = catalog.classify("mystery", {"mystery": {"tier": "fast", "score": 12}})
        self.assertEqual((info.tier, info.score), ("fast", 12))

    def test_not_chat(self):
        self.assertFalse(catalog.is_chat_model("text-embedding-3-large"))
        self.assertFalse(catalog.is_chat_model("whisper-1"))
        self.assertTrue(catalog.is_chat_model("gpt-5.6-luna"))


CLAUDE = {"kind": "claude-code", "models": ["opus", "sonnet", "haiku"]}
CHATGPT = {"kind": "codex", "models": ["gpt-6.1-sol", "gpt-6-luna"]}
DEEPSEEK = {"kind": "openai-compat", "models": ["deepseek-chat", "deepseek-reasoner"]}


def roles(members):
    return {m["id"]: m["model"] for m in members}


class AutoOrg(unittest.TestCase):
    def test_claude_only(self):
        m = roles(org.auto_members({"claude": CLAUDE}))
        self.assertEqual(m["ceo"], "claude:opus")
        self.assertEqual(m["debugger"], "claude:sonnet")    # no other maker; next best
        self.assertEqual([m[f"worker-{i}"] for i in range(1, 5)], ["claude:sonnet"] * 4)

    def test_claude_and_deepseek(self):
        m = roles(org.auto_members({"claude": CLAUDE, "deepseek": DEEPSEEK}))
        self.assertEqual(m["ceo"], "claude:opus")
        self.assertEqual(m["debugger"], "deepseek:deepseek-reasoner")
        self.assertEqual(m["worker-1"], "claude:sonnet")

    def test_the_example(self):
        # Claude + ChatGPT + DeepSeek: Opus CEO, GPT debugger, 4 Sonnet workers.
        members = org.auto_members({"claude": CLAUDE, "chatgpt": CHATGPT, "deepseek": DEEPSEEK})
        m = roles(members)
        self.assertEqual(m["ceo"], "claude:opus")
        self.assertEqual(m["debugger"], "chatgpt:gpt-6.1-sol")
        self.assertEqual([m[f"worker-{i}"] for i in range(1, 5)], ["claude:sonnet"] * 4)
        sub = {x["id"]: x.get("subagent_model") for x in members}
        self.assertEqual(sub["worker-1"], "claude:haiku")
        self.assertEqual(sub["debugger"], "chatgpt:gpt-6-luna")

    def test_spread_and_templates(self):
        accts = {"claude": CLAUDE, "deepseek": DEEPSEEK}
        m = roles(org.auto_members(accts, workers=3, spread=True))
        self.assertEqual({m["worker-1"], m["worker-2"]}, {"claude:sonnet", "deepseek:deepseek-reasoner"})
        self.assertEqual(len(org.auto_members(accts, template="solo")), 1)
        self.assertEqual(len(org.auto_members(accts, template="pair")), 2)
        with self.assertRaises(org.OrgError):
            org.auto_members({})

    def test_hire_fire_set(self):
        accounts = {"claude": CLAUDE, "deepseek": DEEPSEEK}
        company = {"member": org.auto_members(accounts, workers=2), "roles": {
            "designer": {"description": "Makes things look good."}}}
        self.assertEqual(org.hire(company, "worker", "deepseek-chat", accounts), ["worker-3"])
        self.assertEqual(org.hire(company, "designer", "claude:sonnet", accounts), ["designer-1"])
        org.fire(company, "worker-1")
        with self.assertRaises(org.OrgError):
            org.fire(company, "ceo")
        with self.assertRaises(org.OrgError):
            org.hire(company, "ceo", "claude:opus", accounts)
        self.assertEqual(org.hire(company, "worker", "claude:sonnet", accounts), ["worker-1"])
        changed = org.set_model(company, "workers", "claude:haiku", accounts)
        self.assertEqual(sorted(changed), ["worker-1", "worker-2", "worker-3"])
        with self.assertRaises(org.OrgError):
            org.check_ref("nope:x", accounts)
        self.assertEqual(org.validate(company, accounts), [])
        self.assertTrue(org.validate(company, {"claude": CLAUDE}))   # deepseek gone


class Validation(unittest.TestCase):
    def test_ceo_must_be_unique_with_id_ceo(self):
        acc = {"claude": CLAUDE}
        boss = {"member": [{"id": "boss", "role": "ceo", "model": "claude:opus"}]}
        self.assertTrue(org.validate(boss, acc))
        two = {"member": [{"id": "ceo", "role": "ceo", "model": "claude:opus"},
                          {"id": "ceo2", "role": "ceo", "model": "claude:opus"}]}
        self.assertTrue(org.validate(two, acc))
        dup = {"member": [{"id": "ceo", "role": "ceo", "model": "claude:opus"},
                          {"id": "w", "role": "worker", "model": "claude:sonnet"},
                          {"id": "w", "role": "worker", "model": "claude:sonnet"}]}
        self.assertTrue(any("Two members" in p for p in org.validate(dup, acc)))


class Tools(unittest.TestCase):
    def setUp(self):
        from boardroom.company import Spec
        from boardroom.tools import Ctx
        self.ws = Path(tempfile.mkdtemp()).resolve()

        class FakeCompany:
            workspace = self.ws

            def path_lock(self, p):
                import threading
                return threading.Lock()
        self.ctx = Ctx(FakeCompany(), Spec("w", {"id": "w"}, "worker", "a:b", None))

    def test_edit_keeps_crlf(self):
        from boardroom.tools import edit_file
        (self.ws / "x.bat").write_bytes(b"one\r\ntwo\r\n")
        edit_file(self.ctx, {"path": "x.bat", "old_string": "two\r\n", "new_string": "2\r\n"})
        self.assertEqual((self.ws / "x.bat").read_bytes(), b"one\r\n2\r\n")

    def test_shell_background_and_secrets(self):
        import time
        from boardroom.sandbox import Shell
        os.environ["SOME_API_KEY"] = "secret"
        sh = Shell(self.ws, "off", {"CUSTOM_KEY_VAR"})
        os.environ["CUSTOM_KEY_VAR"] = "secret2"
        t = time.time()
        code, out = sh.run("sleep 20 & echo started", timeout=10)
        self.assertLess(time.time() - t, 5)          # doesn't wait for the background job
        self.assertEqual((code, out), (0, "started\n"))
        code, out = sh.run("env")
        self.assertNotIn("secret", out)
        sh.kill_all()
        self.assertEqual(sh._groups, set())


class Conversion(unittest.TestCase):
    MSGS = [
        {"role": "user", "content": "do it"},
        {"role": "assistant", "content": "ok", "tool_calls": [ToolCall("t1", "read_file", {"path": "a"}),
                                                              ToolCall("t2", "list_files", {})]},
        {"role": "tool", "tool_call_id": "t1", "content": "A"},
        {"role": "tool", "tool_call_id": "t2", "content": "a\nb", "is_error": True},
    ]

    def test_anthropic(self):
        out = to_anthropic(self.MSGS)
        self.assertEqual([m["role"] for m in out], ["user", "assistant", "user"])
        self.assertEqual([b["type"] for b in out[1]["content"]], ["text", "tool_use", "tool_use"])
        self.assertEqual([b["tool_use_id"] for b in out[2]["content"]], ["t1", "t2"])
        self.assertTrue(out[2]["content"][1]["is_error"])
        r = from_anthropic({"content": [{"type": "text", "text": "hi"},
                                        {"type": "tool_use", "id": "x", "name": "n", "input": {"a": 1}}],
                            "usage": {"input_tokens": 3, "cache_read_input_tokens": 7, "output_tokens": 2}})
        self.assertEqual((r.text, r.tool_calls[0].args, r.input_tokens), ("hi", {"a": 1}, 10))

    def test_openai(self):
        out = to_openai("sys", self.MSGS)
        self.assertEqual([m["role"] for m in out], ["system", "user", "assistant", "tool", "tool"])
        self.assertEqual(json.loads(out[2]["tool_calls"][0]["function"]["arguments"]), {"path": "a"})
        r = from_openai({"choices": [{"message": {"content": None, "reasoning_content": "hmm",
                                                  "tool_calls": [{"id": "c", "function": {
                                                      "name": "n", "arguments": "{bad"}}]}}]})
        self.assertEqual(r.tool_calls[0].bad_args, "{bad")
        self.assertEqual(r.raw, {"reasoning_content": "hmm"})
        again = to_openai("s", [{"role": "assistant", "content": "", "tool_calls": r.tool_calls, "raw": r.raw}])
        self.assertEqual(again[1]["reasoning_content"], "hmm")


class Prices(unittest.TestCase):
    def test_estimates(self):
        from boardroom import prices
        self.assertAlmostEqual(prices.estimate("claude-opus-5-5", 1_000_000, 1_000_000), 24.0)
        # 600k plain + 400k cache hits at $0.20
        self.assertAlmostEqual(prices.estimate("claude-opus-5-5", 1_000_000, 0, cached=400_000), 2.48)
        # no listed cache price: Anthropic hits cost 10% of input, writes 125%
        self.assertAlmostEqual(prices.estimate("claude-opus-4-8", 1_000_000, 0, cached=500_000,
                                               cache_write=500_000, family="anthropic"), 0.25 + 3.125)
        self.assertAlmostEqual(prices.estimate("anthropic/claude-sonnet-5-5", 1_000_000, 0), 2.0)
        self.assertEqual(prices.estimate("unknown-model", 10**6, 10**6), 0.0)
        o = {"mine": {"price_in": 1, "price_out": 2, "price_cached": 0.5}}
        self.assertAlmostEqual(prices.estimate("mine", 2_000_000, 1_000_000, cached=1_000_000,
                                               overrides=o), 1 + 0.5 + 2)

    def test_usage_details(self):
        r = from_anthropic({"content": [], "stop_reason": "refusal",
                            "stop_details": {"category": "cyber", "explanation": None},
                            "usage": {"input_tokens": 1, "output_tokens": 0}})
        self.assertIn("declined", r.text)
        self.assertIn("cyber", r.text)
        r = from_openai({"choices": [{"message": {"content": "hi"}}],
                         "usage": {"prompt_tokens": 100, "completion_tokens": 5,
                                   "prompt_tokens_details": {"cached_tokens": 60}}})
        self.assertEqual((r.input_tokens, r.cached_tokens), (100, 60))
        r = from_openai({"choices": [{"message": {"content": "hi"}}],
                         "usage": {"prompt_tokens": 100, "prompt_cache_hit_tokens": 30}})
        self.assertEqual(r.cached_tokens, 30)


class Mcp(unittest.TestCase):
    def test_handshake_without_bridge(self):
        env = {**os.environ, "BOARDROOM_BRIDGE": "http://127.0.0.1:9", "BOARDROOM_TOKEN": "t",
               "BOARDROOM_AGENT": "x", "PYTHONPATH": str(Path(__file__).resolve().parent.parent)}
        msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": {"protocolVersion": "2025-03-26"}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "ping"},
                {"jsonrpc": "2.0", "id": 3, "method": "nope"},
                {"jsonrpc": "2.0", "id": 4, "method": "tools/list"}]
        r = subprocess.run([sys.executable, "-m", "boardroom.mcp_server"],
                           input="\n".join(json.dumps(m) for m in msgs) + "\n",
                           capture_output=True, text=True, env=env, timeout=30)
        replies = {j["id"]: j for j in map(json.loads, r.stdout.splitlines())}
        self.assertEqual(replies[1]["result"]["protocolVersion"], "2025-03-26")
        self.assertEqual(replies[2]["result"], {})
        self.assertEqual(replies[3]["error"]["code"], -32601)
        self.assertEqual(replies[4]["error"]["code"], -32603)   # no bridge listening
        self.assertNotIn(None, replies)                         # notifications get no reply


if __name__ == "__main__":
    unittest.main()
