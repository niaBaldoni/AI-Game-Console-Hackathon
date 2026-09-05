"""Small, strict client for the Summer/Godot loopback game bridge."""

from __future__ import annotations

import json
import socket
from typing import Any


MAX_MESSAGE_BYTES = 64 * 1024


class BridgeError(RuntimeError):
    """A user-visible error returned by or connecting to the game bridge."""

    def __init__(self, message: str, *, code: str = "bridge_error") -> None:
        super().__init__(message)
        self.code = code


class BridgeClient:
    def __init__(self, *, host: str, port: int, timeout: float = 1.0) -> None:
        if host != "127.0.0.1" and host != "localhost":
            raise ValueError("The runtime bridge must use a loopback host")
        if not 1 <= port <= 65535:
            raise ValueError("The runtime bridge port is out of range")
        if timeout <= 0:
            raise ValueError("The runtime bridge timeout must be positive")
        self.host = host
        self.port = port
        self.timeout = timeout

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request = {"id": 1, "method": method, "params": params}
        try:
            with socket.create_connection((self.host, self.port), timeout=self.timeout) as connection:
                connection.settimeout(self.timeout)
                connection.sendall(self._encode(request))
                raw_response = self._read_line(connection)
        except (OSError, TimeoutError) as error:
            raise BridgeError(
                "The Summer game is not running or its bridge is unavailable",
                code="game_unavailable",
            ) from error

        try:
            response = json.loads(raw_response.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BridgeError("The game bridge returned invalid JSON", code="bad_bridge_response") from error
        if not isinstance(response, dict):
            raise BridgeError("The game bridge returned a non-object response", code="bad_bridge_response")
        if response.get("ok") is True and isinstance(response.get("result"), dict):
            return response["result"]

        error_payload = response.get("error")
        if isinstance(error_payload, dict):
            code = str(error_payload.get("code", "bridge_error"))
            message = str(error_payload.get("message", "The game bridge rejected the request"))
        else:
            code = "bad_bridge_response"
            message = "The game bridge returned an unsuccessful response"
        raise BridgeError(message, code=code)

    @staticmethod
    def _encode(value: dict[str, Any]) -> bytes:
        payload = (json.dumps(value, separators=(",", ":")) + "\n").encode("utf-8")
        if len(payload) > MAX_MESSAGE_BYTES:
            raise BridgeError("The game bridge request is too large", code="request_too_large")
        return payload

    @staticmethod
    def _read_line(connection: socket.socket) -> bytes:
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            newline = chunk.find(b"\n")
            if newline >= 0:
                chunk = chunk[: newline + 1]
                chunks.append(chunk)
                total += len(chunk)
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_MESSAGE_BYTES:
                raise BridgeError("The game bridge response is too large", code="response_too_large")
        if not chunks:
            raise BridgeError("The game bridge closed without a response", code="bad_bridge_response")
        response = b"".join(chunks)
        if len(response) > MAX_MESSAGE_BYTES:
            raise BridgeError("The game bridge response is too large", code="response_too_large")
        return response.rstrip(b"\r\n")
