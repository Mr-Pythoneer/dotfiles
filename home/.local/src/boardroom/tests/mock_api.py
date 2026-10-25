"""A fake model server for tests. It speaks the Anthropic Messages API and the OpenAI Chat
Completions API, and answers from a script instead of a model, so a whole company can run
offline and deterministically.

script(system, task, step, last_result) returns ("tool", name, args) or ("text", reply), where
task is the first user message, step counts the agent's earlier replies, and last_result is the
text of the latest tool result.
"""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class MockAPI:
    def __init__(self, script):
        self.script = script
        self.calls = []
        mock = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path.startswith("/v1/models"):
                    return self._send({"data": [{"id": "mock-opus"}, {"id": "mock-sonnet"},
                                                {"id": "text-embedding-3"}]})
                self._send({"error": "nope"}, 404)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                mock.calls.append((self.path, body))
                if self.path == "/v1/messages":
                    return self._send(mock._anthropic(body))
                if self.path == "/v1/chat/completions":
                    return self._send(mock._openai(body))
                self._send({"error": "nope"}, 404)

            def _send(self, obj, code=200):
                data = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def _anthropic(self, body):
        system = "".join(b["text"] for b in body["system"])
        msgs = body["messages"]
        task = next(b["text"] for b in msgs[0]["content"] if b["type"] == "text")
        step = sum(1 for m in msgs if m["role"] == "assistant")
        last = ""
        for b in msgs[-1]["content"]:
            if b.get("type") == "tool_result":
                last = b["content"]
        kind, *rest = self.script(system, task, step, last)
        if kind == "tool":
            name, args = rest
            content = [{"type": "tool_use", "id": f"tu_{len(self.calls)}", "name": name, "input": args}]
        else:
            content = [{"type": "text", "text": rest[0]}]
        return {"content": content, "usage": {"input_tokens": 100, "output_tokens": 10}}

    def _openai(self, body):
        msgs = body["messages"]
        system = msgs[0]["content"]
        task = msgs[1]["content"]
        step = sum(1 for m in msgs if m["role"] == "assistant")
        last = msgs[-1]["content"] if msgs[-1]["role"] == "tool" else ""
        kind, *rest = self.script(system, task, step, last)
        if kind == "tool":
            name, args = rest
            msg = {"role": "assistant", "content": None, "tool_calls": [{
                "id": f"call_{len(self.calls)}", "type": "function",
                "function": {"name": name, "arguments": json.dumps(args)}}]}
        else:
            msg = {"role": "assistant", "content": rest[0]}
        return {"choices": [{"message": msg}], "usage": {"prompt_tokens": 50, "completion_tokens": 5}}
