#!/usr/bin/env python3
"""Stands in for the `gemini` CLI in tests. Like `gemini --output-format stream-json`, it reads
the prompt from stdin, finds its MCP servers in the settings file named by
GEMINI_CLI_SYSTEM_SETTINGS_PATH, talks JSON-RPC to them, and prints stream-json events.
The CEO delegates; the worker writes a file and starts a subagent; the subagent writes a file."""

import json
import os
import subprocess
import sys

args = sys.argv[1:]
assert "--skip-trust" in args, args
assert args[args.index("--output-format") + 1] == "stream-json", args
assert args[args.index("--allowed-mcp-server-names") + 1] == "boardroom", args
assert args[args.index("--approval-mode") + 1] in ("yolo", "auto_edit"), args
prompt = sys.stdin.read()
settings = json.load(open(os.environ["GEMINI_CLI_SYSTEM_SETTINGS_PATH"]))
cfg = settings["mcpServers"]["boardroom"]
assert cfg["trust"] is True


def out(obj):
    print(json.dumps({"timestamp": "2026-10-10T12:00:00.000Z", **obj}), flush=True)


srv = subprocess.Popen([cfg["command"], *cfg["args"]], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                       text=True, env={**os.environ, **cfg["env"]}, cwd=cfg["cwd"])
_id = 0


def rpc(method, params=None):
    global _id
    _id += 1
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": _id, "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())


rpc("initialize", {"protocolVersion": "2025-06-18"})
tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
out({"type": "init", "session_id": "gem-1", "model": "auto"})
out({"type": "message", "role": "user", "content": prompt[:50]})


def call(tool, arguments):
    out({"type": "tool_use", "tool_name": f"mcp_boardroom_{tool}", "tool_id": "t", "parameters": arguments})
    text = rpc("tools/call", {"name": tool, "arguments": arguments})["result"]["content"][0]["text"]
    out({"type": "tool_result", "tool_id": "t", "status": "success", "output": text})
    return text


if "You are the CEO" in prompt:
    assert "delegate" in tools and "spawn_subagents" not in tools, tools
    out({"type": "message", "role": "assistant", "content": "Planning: ", "delta": True})
    out({"type": "message", "role": "assistant", "content": "worker-1 makes g.txt.", "delta": True})
    report = call("delegate", {"assignments": [{"to": "worker-1", "task": "write g.txt"}]})
    final = ["CEO saw: ", report]
elif "a subagent working for" in prompt.split("# Your task")[0]:
    assert "spawn_subagents" in tools, tools   # depth 1 < max_depth 2
    with open("sub.txt", "w") as f:
        f.write("S")
    out({"type": "tool_use", "tool_name": "write_file", "tool_id": "w2",
         "parameters": {"file_path": os.path.abspath("sub.txt"), "content": "S"}})
    final = ["sub wrote sub.txt"]
else:
    assert "spawn_subagents" in tools and "delegate" not in tools, tools
    with open("g.txt", "w") as f:
        f.write("G")
    out({"type": "tool_use", "tool_name": "write_file", "tool_id": "w1",
         "parameters": {"file_path": os.path.abspath("g.txt"), "content": "G"}})
    out({"type": "tool_result", "tool_id": "w1", "status": "success"})
    out({"type": "tool_use", "tool_name": "run_shell_command", "tool_id": "s1", "parameters": {"command": "ls"}})
    sub = call("spawn_subagents", {"tasks": ["write sub.txt"]})
    final = ["worker wrote g.txt; ", sub.splitlines()[-1]]

for part in final:
    out({"type": "message", "role": "assistant", "content": part, "delta": True})
srv.stdin.close()
srv.wait(timeout=10)
out({"type": "result", "status": "success", "stats": {
    "total_tokens": 130, "input_tokens": 100, "output_tokens": 30, "cached": 40, "input": 60,
    "duration_ms": 5, "tool_calls": 1,
    "models": {"gemini-3.1-pro-preview": {"input_tokens": 100, "output_tokens": 30, "cached": 40}}}})
