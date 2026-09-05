#!/usr/bin/env python3
"""Cursor MCP server for a running Summer/Godot game.

The process speaks MCP over newline-delimited JSON on stdin/stdout. It talks
to the game bridge over a separate, loopback-only newline-delimited JSON
socket. Keeping the two protocols separate makes the game bridge tiny and
keeps MCP implementation details out of the game.
"""

from __future__ import annotations

import json
import math
import os
import sys
from typing import Any, BinaryIO

from game_client import BridgeClient, BridgeError, FileBridgeClient


SERVER_NAME = "summer-runtime"
SERVER_VERSION = "0.1.0"
SUPPORTED_PROTOCOL_VERSIONS = (
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
)
MAX_MESSAGE_BYTES = 64 * 1024
MEADOW_X_MIN = 24.0
MEADOW_X_MAX = 2376.0
MEADOW_Y_MIN = 24.0
MEADOW_Y_MAX = 1326.0
MIN_ENEMY_HEALTH = 1
MAX_ENEMY_HEALTH = 9

TOOLS = [
    {
        "name": "get_game_state",
        "description": (
            "Read the compact state that the running Summer game publishes "
            "for its agent-controlled opponent."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "set_agent_intent",
        "description": (
            "Change the agent opponent's next allowed intent in the running "
            "Summer game. This changes game-owned state; it cannot execute "
            "scripts or mutate arbitrary scene properties."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "intent": {
                    "type": "string",
                    "enum": ["idle", "left", "right", "act"],
                    "description": "The opponent intent to publish.",
                }
            },
            "required": ["intent"],
            "additionalProperties": False,
        },
    },
    {
        "name": "spawn_enemy",
        "description": (
            "Queue one real-time enemy spawn in the running Open Meadow. "
            "Pass kind brute (melee) or mage (ranged). The game owns the enemy node "
            "and enforces its live roster limit."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {
                    "type": "number",
                    "minimum": MEADOW_X_MIN,
                    "maximum": MEADOW_X_MAX,
                    "description": "Enemy X coordinate inside the meadow.",
                },
                "y": {
                    "type": "number",
                    "minimum": MEADOW_Y_MIN,
                    "maximum": MEADOW_Y_MAX,
                    "description": "Enemy Y coordinate inside the meadow.",
                },
                "kind": {
                    "type": "string",
                    "enum": ["brute", "melee", "mage", "ranged"],
                    "description": "Enemy kind to spawn. brute/melee or mage/ranged. Defaults to brute.",
                },
                "health": {
                    "type": "integer",
                    "minimum": MIN_ENEMY_HEALTH,
                    "maximum": MAX_ENEMY_HEALTH,
                    "description": "Optional health override; omitted uses the kind default.",
                },
            },
            "required": ["x", "y"],
            "additionalProperties": False,
        },
    },
]


def _json_line(value: Any) -> bytes:
    """Encode one protocol message without embedded newlines."""

    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _write_message(stream: BinaryIO, value: Any) -> None:
    stream.write(_json_line(value))
    stream.flush()


def _error_response(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }


def _text_result(payload: dict[str, Any], *, is_error: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {
        "content": [
            {
                "type": "text",
                "text": json.dumps(payload, ensure_ascii=False, sort_keys=True),
            }
        ],
        "structuredContent": payload,
    }
    if is_error:
        result["isError"] = True
    return result


def _selected_protocol_version(params: dict[str, Any]) -> str:
    requested = params.get("protocolVersion")
    if requested in SUPPORTED_PROTOCOL_VERSIONS:
        return requested
    # MCP clients commonly send the newest version first. Returning a known
    # version makes the compatibility decision explicit instead of echoing an
    # unsupported value.
    return SUPPORTED_PROTOCOL_VERSIONS[0]


class RuntimeMcpServer:
    def __init__(self, bridge: BridgeClient) -> None:
        self.bridge = bridge

    def handle(self, request: dict[str, Any]) -> dict[str, Any] | None:
        request_id = request.get("id")
        method = request.get("method")

        # Notifications do not receive responses in JSON-RPC/MCP.
        if isinstance(method, str) and method.startswith("notifications/"):
            return None

        if not isinstance(method, str):
            return _error_response(request_id, -32600, "Request method must be a string")

        params = request.get("params", {})
        if not isinstance(params, dict):
            return _error_response(request_id, -32602, "Request params must be an object")

        if method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "protocolVersion": _selected_protocol_version(params),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                    "instructions": (
                        "Use get_game_state to observe the running game and "
                        "set_agent_intent to control only the game-owned opponent intent."
                    ),
                },
            }

        if method == "ping":
            return {"jsonrpc": "2.0", "id": request_id, "result": {}}

        if method == "tools/list":
            return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}

        if method == "tools/call":
            return self._handle_tool_call(request_id, params)

        return _error_response(request_id, -32601, f"Method not found: {method}")

    def _handle_tool_call(self, request_id: Any, params: dict[str, Any]) -> dict[str, Any]:
        name = params.get("name")
        arguments = params.get("arguments", {})
        if not isinstance(name, str):
            return _error_response(request_id, -32602, "Tool name must be a string")
        if not isinstance(arguments, dict):
            return _error_response(request_id, -32602, "Tool arguments must be an object")

        if name == "get_game_state":
            if arguments:
                return _error_response(
                    request_id, -32602, "get_game_state does not accept arguments"
                )
            bridge_method = "get_game_state"
            bridge_params: dict[str, Any] = {}
        elif name == "set_agent_intent":
            if set(arguments) != {"intent"} or not isinstance(arguments.get("intent"), str):
                return _error_response(
                    request_id,
                    -32602,
                    "set_agent_intent requires only a string intent",
                )
            bridge_method = "set_agent_intent"
            bridge_params = {"intent": arguments["intent"]}
        elif name == "spawn_enemy":
            invalid_keys = set(arguments) - {"x", "y", "health", "kind"}
            if invalid_keys or "x" not in arguments or "y" not in arguments:
                return _error_response(
                    request_id,
                    -32602,
                    "spawn_enemy requires x, y, and optional kind and health",
                )

            x = arguments["x"]
            y = arguments["y"]
            if not self._valid_number(x) or not self._valid_number(y):
                return _error_response(request_id, -32602, "spawn_enemy x and y must be finite numbers")
            if not MEADOW_X_MIN <= float(x) <= MEADOW_X_MAX:
                return _error_response(request_id, -32602, "spawn_enemy x is outside the meadow")
            if not MEADOW_Y_MIN <= float(y) <= MEADOW_Y_MAX:
                return _error_response(request_id, -32602, "spawn_enemy y is outside the meadow")

            kind = arguments.get("kind", "brute")
            if not isinstance(kind, str):
                return _error_response(request_id, -32602, "spawn_enemy kind must be a string")
            normalized_kind = self._normalize_kind(kind)
            if not normalized_kind:
                return _error_response(request_id, -32602, "spawn_enemy kind must be brute, melee, mage, or ranged")

            bridge_params = {"x": float(x), "y": float(y), "kind": normalized_kind}
            if "health" in arguments:
                health = arguments["health"]
                if isinstance(health, bool) or not isinstance(health, int):
                    return _error_response(request_id, -32602, "spawn_enemy health must be an integer")
                if not MIN_ENEMY_HEALTH <= health <= MAX_ENEMY_HEALTH:
                    return _error_response(request_id, -32602, "spawn_enemy health is outside the allowed range")
                bridge_params["health"] = health

            bridge_method = "spawn_enemy"
        else:
            return _error_response(request_id, -32601, f"Unknown tool: {name}")

        try:
            payload = self.bridge.request(bridge_method, bridge_params)
        except BridgeError as error:
            error_payload = {"error": error.code, "message": str(error)}
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": _text_result(error_payload, is_error=True),
            }

        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": _text_result(payload),
        }

    @staticmethod
    def _normalize_kind(value: str) -> str:
        key = value.strip().lower()
        if key in {"melee", "brute"}:
            return "brute"
        if key in {"mage", "ranged"}:
            return "mage"
        return ""

    @staticmethod
    def _valid_number(value: Any) -> bool:
        return (
            not isinstance(value, bool)
            and isinstance(value, (int, float))
            and math.isfinite(float(value))
        )


def _parse_line(raw_line: bytes) -> dict[str, Any]:
    if len(raw_line) > MAX_MESSAGE_BYTES:
        raise ValueError("MCP message exceeds the size limit")
    try:
        value = json.loads(raw_line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("MCP message is not valid UTF-8 JSON") from error
    if not isinstance(value, dict) or value.get("jsonrpc") != "2.0":
        raise ValueError("MCP message must be a JSON-RPC 2.0 object")
    return value


def main() -> int:
    timeout = float(os.environ.get("SUMMER_GAME_MCP_TIMEOUT", "1.0"))
    file_directory = os.environ.get("SUMMER_GAME_MCP_DIR", "").strip()
    if file_directory:
        try:
            bridge = FileBridgeClient(directory=file_directory, timeout=timeout)
            print(f"runtime-mcp: using shared file bridge {file_directory}", file=sys.stderr)
        except (BridgeError, ValueError) as error:
            print(f"runtime-mcp: file bridge unavailable ({error}); using TCP", file=sys.stderr)
            bridge = BridgeClient(
                host=os.environ.get("SUMMER_GAME_MCP_HOST", "127.0.0.1"),
                port=int(os.environ.get("SUMMER_GAME_MCP_PORT", "8765")),
                timeout=timeout,
            )
    else:
        bridge = BridgeClient(
            host=os.environ.get("SUMMER_GAME_MCP_HOST", "127.0.0.1"),
            port=int(os.environ.get("SUMMER_GAME_MCP_PORT", "8765")),
            timeout=timeout,
        )
    server = RuntimeMcpServer(bridge)

    for raw_line in sys.stdin.buffer:
        if not raw_line.strip():
            continue
        request_id: Any = None
        try:
            request = _parse_line(raw_line.rstrip(b"\r\n"))
            request_id = request.get("id")
            response = server.handle(request)
        except ValueError as error:
            response = _error_response(request_id, -32700, str(error))
        except Exception as error:  # Keep a protocol error from killing Cursor's session.
            print(f"runtime-mcp internal error: {error}", file=sys.stderr)
            response = _error_response(request_id, -32603, "Internal MCP server error")

        if response is not None:
            _write_message(sys.stdout.buffer, response)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
