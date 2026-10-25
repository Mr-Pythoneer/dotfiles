"""The web UI's server: access control, account and team changes, and a whole run (start,
event stream, reply, finish, history) against the mock API."""

import json
import os
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

os.environ.setdefault("BOARDROOM_HOME", tempfile.mkdtemp(prefix="boardroom-test-home-"))

from boardroom import config, web  # noqa: E402
from tests.mock_api import MockAPI  # noqa: E402


def script(system, task, step, last):
    if "You are the CEO" in system:
        if step == 0:
            return "tool", "delegate", {"assignments": [{"to": "worker-1", "task": "write w.txt"}]}
        return "text", f"## Report\n\nround {step}: done"
    if step == 0:
        return "tool", "write_file", {"path": "w.txt", "content": "W"}
    return "text", "wrote w.txt"


class WebApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = Path(tempfile.mkdtemp(prefix="boardroom-web-home-"))
        os.environ["BOARDROOM_HOME"] = str(cls.home)
        cls.mock = MockAPI(script)
        cls.ws = Path(tempfile.mkdtemp(prefix="boardroom-web-ws-")).resolve()
        cls.app = web.App(cls.ws)
        box = {"port": 0}
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), web.make_handler(cls.app, box))
        cls.srv.daemon_threads = True
        box["port"] = cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.app.shutdown()
        cls.srv.shutdown()
        cls.srv.server_close()
        cls.mock.close()

    def call(self, path, body=None, token=True, host=None):
        headers = {"content-type": "application/json"}
        if token:
            headers["x-boardroom-token"] = self.app.token
        if host:
            headers["host"] = host
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", headers=headers,
                                     data=None if body is None else json.dumps(body).encode(),
                                     method="GET" if body is None else "POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            with e:
                return e.code, json.loads(e.read() or b"{}")

    def wait_state(self, want, timeout=20):
        end = time.time() + timeout
        while time.time() < end:
            if self.call("/api/state")[1]["run"]["state"] == want:
                return
            time.sleep(0.1)
        self.fail(f"run never reached {want!r}")

    def events(self, start=0, gen=0, seconds=1.0):
        """Read the event stream for a moment."""
        url = f"http://127.0.0.1:{self.port}/api/events?from={start}&gen={gen}&t={self.app.token}"
        out = []
        with urllib.request.urlopen(url, timeout=seconds) as r:
            try:
                kind = None
                for raw in r:
                    line = raw.decode().rstrip("\n")
                    if line.startswith("event: "):
                        kind = line[7:]
                    elif line.startswith("data: "):
                        out.append((kind, json.loads(line[6:])))
            except (TimeoutError, OSError):
                pass
        return out

    def test_1_access(self):
        self.assertEqual(self.call("/api/state", token=False)[0], 401)
        self.assertEqual(self.call("/api/state", host="evil.example")[0], 403)
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/") as r:
            self.assertIn(b"Boardroom", r.read())
            self.assertIn("default-src 'self'", r.headers["content-security-policy"])
        self.assertEqual(self.call("/../boardroom/web.py", token=False)[0], 404)

    def test_2_accounts_and_team(self):
        code, j = self.call("/api/connect", {"provider": "custom", "name": "mock",
                                             "base_url": self.mock.url + "/v1", "key": "sk-x"})
        self.assertEqual(code, 200, j)
        st = self.call("/api/state")[1]
        acc = st["accounts"][0]
        self.assertEqual((acc["name"], acc["has_key"]), ("mock", True))
        self.assertNotIn("key", acc)                       # keys never go to the page
        self.assertEqual([m["id"] for m in st["members"]][:2], ["ceo", "debugger"])  # auto team
        self.assertEqual(self.call("/api/connect", {"provider": "nope"})[0], 400)
        self.assertEqual(self.call("/api/org/auto", {"workers": 1, "template": "startup"})[0], 200)
        self.assertEqual([m["id"] for m in self.call("/api/state")[1]["members"]],
                         ["ceo", "debugger", "worker-1"])
        self.assertEqual(self.call("/api/hire", {"role": "worker", "model": "mock:mock-sonnet"})[0], 200)
        self.assertEqual(self.call("/api/fire", {"id": "worker-2"})[0], 200)
        self.assertEqual(self.call("/api/fire", {"id": "ceo"})[0], 400)
        self.assertEqual(self.call("/api/org/set", {"who": "ceo", "model": "mock:mock-opus"})[0], 200)
        self.assertEqual(self.call("/api/settings", {"autonomy": "nope"})[0], 400)
        self.assertEqual(self.call("/api/settings", {"name": "Web Co", "max_steps": "30"})[0], 200)
        self.assertEqual(config.load_company()["max_steps"], 30)
        self.assertEqual(self.call("/api/test", {"name": "mock"})[1]["ok"], True)
        models = self.call("/api/models")[1]
        self.assertIn("mock:mock-opus", [m["ref"] for m in models])

    def test_3_run(self):
        code, j = self.call("/api/run", {"goal": "make w.txt", "dir": str(self.ws)})
        self.assertEqual(code, 200, j)
        self.assertEqual(self.call("/api/run", {"goal": "again", "dir": str(self.ws)})[0], 400)
        self.wait_state("waiting")
        evs = self.events()
        self.assertEqual(evs[0], ("reset", {"generation": self.app.generation}))
        types = [d["type"] for k, d in evs if k == "event"]
        self.assertEqual(types[0], "run_start")
        self.assertIn("delegate", types)
        report = [d for k, d in evs if k == "event" and d["type"] == "report" and d["agent"] == "ceo"]
        self.assertIn("round 1", report[-1]["text"])
        self.assertEqual((self.ws / "w.txt").read_text(), "W")
        # resuming the stream from event 3 gives only the rest
        later = self.events(start=3, gen=self.app.generation)
        self.assertEqual(len([1 for k, _ in later if k == "event"]), len(types) - 3)
        # a reply continues with the same CEO
        self.assertEqual(self.call("/api/reply", {"text": "and more"})[0], 200)
        self.wait_state("waiting")
        self.assertEqual(self.call("/api/finish", {})[0], 200)
        self.assertEqual(self.call("/api/state")[1]["run"]["state"], "finished")
        runs = self.call(f"/api/runs?dir={self.ws}")[1]
        self.assertEqual((runs[0]["goal"], runs[0]["ok"]), ("make w.txt", True))
        detail = self.call(f"/api/run?dir={self.ws}&name={runs[0]['name']}")[1]
        self.assertIn("round 2", detail["report"])
        self.assertEqual(self.call(f"/api/run?dir={self.ws}&name=..")[0], 404)

    def test_4_folders(self):
        d = self.call(f"/api/dirs?path={self.ws}")[1]
        self.assertEqual(d["path"], str(self.ws))
        code, j = self.call("/api/mkdir", {"path": str(self.ws / "new project")})
        self.assertEqual(code, 200, j)
        self.assertIn("new project", self.call(f"/api/dirs?path={self.ws}")[1]["dirs"])
        self.assertEqual(self.call("/api/mkdir", {"path": "relative"})[0], 400)


if __name__ == "__main__":
    unittest.main()
