#!/usr/bin/env python3
"""Cursor MCP server for a running Summer/Godot game.

The process speaks MCP over newline-delimited JSON on stdin/stdout. It talks
to the game bridge over a separate, loopback-only newline-delimited JSON
socket. Keeping the two protocols separate makes the game bridge tiny and
keeps MCP implementation details out of the game.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any, BinaryIO

from game_client import BridgeClient, BridgeError


SERVER_NAME = "summer-runtime"
SERVER_VERSION = "0.1.0"
SUPPORTED_PROTOCOL_VERSIONS = (
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
)
MAX_MESSAGE_BYTES = 64 * 1024

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
    bridge = BridgeClient(
        host=os.environ.get("SUMMER_GAME_MCP_HOST", "127.0.0.1"),
        port=int(os.environ.get("SUMMER_GAME_MCP_PORT", "8765")),
        timeout=float(os.environ.get("SUMMER_GAME_MCP_TIMEOUT", "1.0")),
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
