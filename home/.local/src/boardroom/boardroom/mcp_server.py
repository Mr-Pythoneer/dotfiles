"""A minimal MCP server (stdio, JSON-RPC) that forwards tool calls to the Boardroom bridge.

A CLI member (Claude Code, Codex) starts this as a subprocess. It reads three environment
variables: BOARDROOM_BRIDGE (url), BOARDROOM_TOKEN, BOARDROOM_AGENT (which agent it serves).
"""

from __future__ import annotations

import json
import os
import sys
import threading
import urllib.request

from boardroom import __version__

_out = threading.Lock()


def send(msg: dict) -> None:
    with _out:
        sys.stdout.write(json.dumps(msg) + "\n")
        sys.stdout.flush()


def post(path: str, body: dict) -> dict:
    req = urllib.request.Request(
        os.environ["BOARDROOM_BRIDGE"] + path, data=json.dumps(body).encode(), method="POST",
        headers={"content-type": "application/json",
                 "authorization": f"Bearer {os.environ['BOARDROOM_TOKEN']}"})
    with urllib.request.urlopen(req, timeout=None) as r:   # delegate can take a long time
        return json.loads(r.read())


def handle(msg: dict) -> None:
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:
        return   # a notification; nothing to answer
    agent = os.environ.get("BOARDROOM_AGENT", "")
    try:
        if method == "initialize":
            version = (msg.get("params") or {}).get("protocolVersion") or "2025-06-18"
            result = {"protocolVersion": version, "capabilities": {"tools": {}},
                      "serverInfo": {"name": "boardroom", "version": __version__}}
        elif method == "tools/list":
            result = {"tools": post("/tools", {"agent": agent})["tools"]}
        elif method == "tools/call":
            p = msg.get("params") or {}
            r = post("/call", {"agent": agent, "tool": p.get("name"), "args": p.get("arguments")})
            result = {"content": [{"type": "text", "text": r["text"]}], "isError": r["is_error"]}
        elif method == "ping":
            result = {}
        else:
            send({"jsonrpc": "2.0", "id": mid,
                  "error": {"code": -32601, "message": f"unknown method {method}"}})
            return
        send({"jsonrpc": "2.0", "id": mid, "result": result})
    except Exception as e:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32603, "message": str(e)}})


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("method") == "tools/call":
            # Tool calls (like delegate) can take minutes; keep answering pings meanwhile.
            threading.Thread(target=handle, args=(msg,), daemon=True).start()
        else:
            handle(msg)


if __name__ == "__main__":
    main()
