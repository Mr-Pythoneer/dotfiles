#!/usr/bin/env python3
"""Stands in for the `claude` CLI in tests. It behaves like `claude -p --output-format
stream-json`: reads the prompt from stdin, starts the MCP servers from --mcp-config and talks
JSON-RPC to them, and prints stream-json events. The CEO delegates through MCP; workers write a
file and use a native subagent."""

import json
import os
import subprocess
import sys

args = sys.argv[1:]
if args[:2] == ["auth", "status"]:
    print(json.dumps({"loggedIn": True, "authMethod": "claude.ai", "subscriptionType": "max"}))
    sys.exit(0)


def opt(name):
    return args[args.index(name) + 1] if name in args else None


def out(obj):
    print(json.dumps(obj), flush=True)


system = opt("--append-system-prompt") or ""
prompt = sys.stdin.read()
mcp_cfg = json.loads(opt("--mcp-config"))["mcpServers"]["boardroom"]
assert "mcp__boardroom__*" in args, args
assert "--permission-mode" in args, args

srv = subprocess.Popen([mcp_cfg["command"], *mcp_cfg["args"]], stdin=subprocess.PIPE,
                       stdout=subprocess.PIPE, text=True, env={**os.environ, **mcp_cfg["env"]})
_id = 0


def rpc(method, params=None):
    global _id
    _id += 1
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": _id, "method": method,
                                "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())


init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}})
assert init["result"]["serverInfo"]["name"] == "boardroom"
srv.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
srv.stdin.flush()
tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]

out({"type": "system", "subtype": "init", "session_id": "sess-1",
     "mcp_servers": [{"name": "boardroom", "status": "connected"}], "tools": tools})

if "You are the CEO" in system:
    assert "delegate" in tools, tools
    assert "spawn_subagents" not in tools, tools   # Claude Code has its own subagents
    out({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [
        {"type": "text", "text": "Planning: worker-1 makes c.txt."},
        {"type": "tool_use", "id": "t1", "name": "mcp__boardroom__delegate", "input": {}}]}})
    r = rpc("tools/call", {"name": "delegate", "arguments": {
        "assignments": [{"to": "worker-1", "task": "write c.txt"}]}})
    report = r["result"]["content"][0]["text"]
    final = f"CEO saw: {report}"
else:
    assert "delegate" not in tools, tools
    with open("c.txt", "w") as f:
        f.write("C")
    out({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_use", "id": "t2", "name": "Write",
         "input": {"file_path": os.path.abspath("c.txt"), "content": "C"}},
        {"type": "tool_use", "id": "t3", "name": "Agent",
         "input": {"description": "double-check c.txt", "prompt": "check"}}]}})
    out({"type": "assistant", "parent_tool_use_id": "t3", "message": {"content": [
        {"type": "tool_use", "id": "t4", "name": "Bash", "input": {"command": "cat c.txt"}}]}})
    out({"type": "user", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_result", "tool_use_id": "t3", "content": [{"type": "text", "text": "c.txt is fine"}]}]}})
    final = f"worker wrote c.txt (prompt was: {prompt.strip()})"

srv.stdin.close()
srv.wait(timeout=10)
out({"type": "result", "subtype": "success", "is_error": False, "result": final,
     "session_id": "sess-1", "num_turns": 2, "total_cost_usd": 0.01,
     "usage": {"input_tokens": 10, "output_tokens": 5},
     "modelUsage": {"m": {"inputTokens": 40, "outputTokens": 20, "cacheReadInputTokens": 60}}})
