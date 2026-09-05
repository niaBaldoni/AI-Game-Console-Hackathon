from __future__ import annotations

import json
import os
import socketserver
import subprocess
import sys
import threading
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from game_client import BridgeClient  # noqa: E402


class MockState:
    def __init__(self) -> None:
        self.intent = "idle"
        self.revision = 0

    def state(self) -> dict[str, Any]:
        return {
            "agent_intent": self.intent,
            "revision": self.revision,
            "summary": {"mock": True},
        }


class MockBridgeHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        line = self.rfile.readline(64 * 1024)
        request = json.loads(line)
        method = request.get("method")
        params = request.get("params", {})
        if method == "get_game_state":
            response = {"ok": True, "result": self.server.state.state()}  # type: ignore[attr-defined]
        elif method == "set_agent_intent" and params.get("intent") in {"idle", "left", "right", "act"}:
            state = self.server.state  # type: ignore[attr-defined]
            if params["intent"] != state.intent:
                state.intent = params["intent"]
                state.revision += 1
            response = {"ok": True, "result": state.state()}
        else:
            response = {
                "ok": False,
                "error": {"code": "invalid_intent", "message": "Intent is not allowed"},
            }
        self.wfile.write((json.dumps(response) + "\n").encode("utf-8"))


class MockBridgeServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

    def __init__(self) -> None:
        super().__init__(("127.0.0.1", 0), MockBridgeHandler)
        self.state = MockState()


class RuntimeMcpTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge = MockBridgeServer()
        self.thread = threading.Thread(target=self.bridge.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.bridge.shutdown()
        self.bridge.server_close()
        self.thread.join(timeout=2)

    def test_bridge_client_changes_allowed_state(self) -> None:
        client = BridgeClient(host="127.0.0.1", port=self.bridge.server_address[1])
        before = client.request("get_game_state", {})
        self.assertEqual(before["agent_intent"], "idle")
        after = client.request("set_agent_intent", {"intent": "right"})
        self.assertEqual(after["agent_intent"], "right")
        self.assertEqual(after["revision"], 1)

    def test_stdio_mcp_discovers_and_calls_tools(self) -> None:
        env = os.environ.copy()
        env["SUMMER_GAME_MCP_PORT"] = str(self.bridge.server_address[1])
        process = subprocess.Popen(
            [sys.executable, str(ROOT / "server.py")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        requests = [
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {}},
            },
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "set_agent_intent", "arguments": {"intent": "left"}},
            },
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {"name": "get_game_state", "arguments": {}},
            },
        ]
        stdin_payload = b"".join(
            (json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8")
            for request in requests
        )
        stdout, stderr = process.communicate(stdin_payload, timeout=5)
        self.assertEqual(process.returncode, 0, stderr.decode("utf-8"))
        responses = [json.loads(line) for line in stdout.splitlines()]
        self.assertEqual(len(responses), 4)
        self.assertEqual(responses[0]["result"]["serverInfo"]["name"], "summer-runtime")
        tool_names = [tool["name"] for tool in responses[1]["result"]["tools"]]
        self.assertEqual(tool_names, ["get_game_state", "set_agent_intent"])
        self.assertEqual(responses[2]["result"]["structuredContent"]["agent_intent"], "left")
        self.assertEqual(responses[3]["result"]["structuredContent"]["revision"], 1)


if __name__ == "__main__":
    unittest.main()
