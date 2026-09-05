"""Small, strict client for the Summer/Godot loopback game bridge."""

from __future__ import annotations

import json
import os
import socket
import tempfile
import time
import uuid
from pathlib import Path
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


class FileBridgeClient:
    """Client for the shared app-mount transport used by Uno Q deployments."""

    def __init__(self, *, directory: str, timeout: float = 1.0) -> None:
        if timeout <= 0:
            raise ValueError("The runtime bridge timeout must be positive")
        path = Path(directory).expanduser()
        if not path.is_absolute():
            raise ValueError("The file bridge directory must be absolute")
        try:
            path.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            raise BridgeError(
                "The shared game bridge directory is unavailable",
                code="file_bridge_unavailable",
            ) from error
        self.directory = path
        self.timeout = timeout

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = uuid.uuid4().hex
        request_path = self.directory / f"request-{request_id}.json"
        response_path = self.directory / f"response-{request_id}.json"
        payload = {"id": request_id, "method": method, "params": params}

        try:
            self._write_atomically(request_path, payload)
            deadline = time.monotonic() + self.timeout
            while time.monotonic() < deadline:
                if response_path.exists():
                    response = self._read_response(response_path)
                    response_path.unlink(missing_ok=True)
                    return self._unwrap_response(response)
                time.sleep(0.02)
        except (OSError, TimeoutError) as error:
            raise BridgeError(
                "The shared game bridge is unavailable",
                code="game_unavailable",
            ) from error
        finally:
            request_path.unlink(missing_ok=True)
            response_path.unlink(missing_ok=True)

        raise BridgeError(
            "The Summer game is not running or its file bridge is unavailable",
            code="game_unavailable",
        )

    @staticmethod
    def _write_atomically(path: Path, value: dict[str, Any]) -> None:
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if len(encoded.encode("utf-8")) > MAX_MESSAGE_BYTES:
            raise BridgeError("The file bridge request is too large", code="request_too_large")
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
        ) as temporary:
            temporary.write(encoded)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, path)

    @staticmethod
    def _read_response(path: Path) -> dict[str, Any]:
        raw = path.read_bytes()
        if len(raw) > MAX_MESSAGE_BYTES:
            raise BridgeError("The file bridge response is too large", code="response_too_large")
        try:
            response = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BridgeError("The file bridge returned invalid JSON", code="bad_bridge_response") from error
        if not isinstance(response, dict):
            raise BridgeError("The file bridge returned a non-object response", code="bad_bridge_response")
        return response

    @staticmethod
    def _unwrap_response(response: dict[str, Any]) -> dict[str, Any]:
        if response.get("ok") is True and isinstance(response.get("result"), dict):
            return response["result"]
        error_payload = response.get("error")
        if isinstance(error_payload, dict):
            code = str(error_payload.get("code", "bridge_error"))
            message = str(error_payload.get("message", "The game bridge rejected the request"))
        else:
            code = "bad_bridge_response"
            message = "The file bridge returned an unsuccessful response"
        raise BridgeError(message, code=code)
