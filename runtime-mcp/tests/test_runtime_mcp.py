from __future__ import annotations

import json
import os
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from game_client import BridgeClient, FileBridgeClient  # noqa: E402


class MockState:
    def __init__(self) -> None:
        self.intent = "idle"
        self.revision = 0
        self.next_enemy_id = 1
        self.enemies: list[dict[str, Any]] = []

    def state(self) -> dict[str, Any]:
        return {
            "agent_intent": self.intent,
            "revision": self.revision,
            "summary": {"mock": True},
            "enemies": list(self.enemies),
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
        elif method == "spawn_enemy":
            state = self.server.state  # type: ignore[attr-defined]
            enemy = {
                "id": state.next_enemy_id,
                "position": {"x": params["x"], "y": params["y"]},
                "health": params.get("health", 3),
                "max_health": params.get("health", 3),
                "alive": True,
                "kind": params.get("kind", "brute"),
            }
            state.next_enemy_id += 1
            state.enemies.append(enemy)
            response = {
                "ok": True,
                "result": {
                    "queued": True,
                    "spawned": True,
                    "request_id": enemy["id"],
                    "position": enemy["position"],
                    "health": enemy["health"],
                    "kind": enemy["kind"],
                },
            }
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

        spawned = client.request("spawn_enemy", {"x": 720.0, "y": 360.0, "health": 4})
        self.assertTrue(spawned["queued"])
        self.assertEqual(spawned["health"], 4)
        mage = client.request("spawn_enemy", {"x": 800.0, "y": 400.0, "kind": "mage"})
        self.assertEqual(mage["kind"], "mage")
        self.assertEqual(client.request("get_game_state", {})["enemies"][0]["id"], 1)

    def test_file_bridge_client_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)

            def game_worker() -> None:
                deadline = time.monotonic() + 2.0
                request_path: Path | None = None
                while time.monotonic() < deadline:
                    requests = list(directory_path.glob("request-*.json"))
                    if requests:
                        request_path = requests[0]
                        break
                    time.sleep(0.01)
                if request_path is None:
                    raise AssertionError("file bridge request was not written")

                request = json.loads(request_path.read_text(encoding="utf-8"))
                response_path = directory_path / f"response-{request['id']}.json"
                temporary_path = directory_path / f".response-{request['id']}.tmp"
                temporary_path.write_text(
                    json.dumps(
                        {
                            "id": request["id"],
                            "ok": True,
                            "result": {
                                "agent_intent": "idle",
                                "revision": 1,
                                "summary": {"file_mock": True},
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                temporary_path.replace(response_path)

            worker = threading.Thread(target=game_worker)
            worker.start()
            state = FileBridgeClient(directory=directory, timeout=2.0).request(
                "get_game_state", {}
            )
            worker.join(timeout=2.0)

        self.assertEqual(state["summary"]["file_mock"], True)
        self.assertEqual(state["revision"], 1)

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
            {
                "jsonrpc": "2.0",
                "id": 5,
                "method": "tools/call",
                "params": {
                    "name": "spawn_enemy",
                    "arguments": {"x": 720, "y": 360, "health": 4},
                },
            },
            {
                "jsonrpc": "2.0",
                "id": 6,
                "method": "tools/call",
                "params": {"name": "get_game_state", "arguments": {}},
            },
            {
                "jsonrpc": "2.0",
                "id": 7,
                "method": "tools/call",
                "params": {
                    "name": "spawn_enemy",
                    "arguments": {"x": 2400, "y": 360, "health": 4},
                },
            },
        ]
        stdin_payload = b"".join(
            (json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8")
            for request in requests
        )
        stdout, stderr = process.communicate(stdin_payload, timeout=5)
        self.assertEqual(process.returncode, 0, stderr.decode("utf-8"))
        responses = [json.loads(line) for line in stdout.splitlines()]
        self.assertEqual(len(responses), 7)
        self.assertEqual(responses[0]["result"]["serverInfo"]["name"], "summer-runtime")
        tool_names = [tool["name"] for tool in responses[1]["result"]["tools"]]
        self.assertEqual(tool_names, ["get_game_state", "set_agent_intent", "spawn_enemy"])
        self.assertEqual(responses[2]["result"]["structuredContent"]["agent_intent"], "left")
        self.assertEqual(responses[3]["result"]["structuredContent"]["revision"], 1)
        self.assertTrue(responses[4]["result"]["structuredContent"]["queued"])
        self.assertEqual(responses[5]["result"]["structuredContent"]["enemies"][0]["health"], 4)
        self.assertEqual(responses[6]["error"]["code"], -32602)


if __name__ == "__main__":
    unittest.main()
