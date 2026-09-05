extends Node
class_name AgentBridge

## Loopback bridge between a running Summer/Godot game and runtime-mcp/server.py.
## Add this script as an Autoload named "AgentBridge" in the game project.

signal agent_intent_changed(intent: String)

@export var listen_host: String = "127.0.0.1"
@export var listen_port: int = 8765

const MAX_MESSAGE_BYTES := 64 * 1024
const ALLOWED_INTENTS := ["idle", "left", "right", "act"]

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _agent_intent := "idle"
var _revision := 0
var _summary: Dictionary = {}


func _ready() -> void:
	var error := _server.listen(listen_port, listen_host)
	if error != OK:
		push_error("AgentBridge could not listen on %s:%d (error %d)" % [listen_host, listen_port, error])
		return
	set_process(true)


func _exit_tree() -> void:
	for client_entry in _clients:
		var peer: StreamPeerTCP = client_entry["peer"]
		peer.disconnect_from_host()
	_clients.clear()
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		_clients.append({"peer": peer, "buffer": PackedByteArray()})

	for index in range(_clients.size() - 1, -1, -1):
		var client_entry: Dictionary = _clients[index]
		var peer: StreamPeerTCP = client_entry["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(index)
			continue

		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var packet := peer.get_data(available)
		if packet[0] != OK:
			peer.disconnect_from_host()
			_clients.remove_at(index)
			continue

		var buffer: PackedByteArray = client_entry["buffer"]
		buffer.append_array(packet[1])
		if buffer.size() > MAX_MESSAGE_BYTES:
			_send_error_and_close(peer, "request_too_large", "The bridge request is too large")
			_clients.remove_at(index)
			continue

		var newline := buffer.find(10)
		if newline < 0:
			client_entry["buffer"] = buffer
			_clients[index] = client_entry
			continue

		var line := buffer.slice(0, newline).get_string_from_utf8()
		var response := _handle_request(line)
		_send_and_close(peer, response)
		_clients.remove_at(index)


func publish_summary(summary: Dictionary) -> void:
	## Called by game logic to publish a small, JSON-safe observation.
	_summary = summary.duplicate(true)


func get_game_state() -> Dictionary:
	return {
		"agent_intent": _agent_intent,
		"revision": _revision,
		"summary": _summary.duplicate(true),
	}


func set_agent_intent(intent: String) -> Dictionary:
	if not ALLOWED_INTENTS.has(intent):
		push_warning("Rejected agent intent: %s" % intent)
		return {}
	if intent != _agent_intent:
		_agent_intent = intent
		_revision += 1
		agent_intent_changed.emit(intent)
	return get_game_state()


func _handle_request(line: String) -> Dictionary:
	var request_variant = JSON.parse_string(line)
	if not (request_variant is Dictionary):
		return {"ok": false, "error": {"code": "invalid_json", "message": "Request must be a JSON object"}}

	var method = request_variant.get("method", "")
	var params = request_variant.get("params", {})
	if not (method is String) or not (params is Dictionary):
		return {"ok": false, "error": {"code": "invalid_request", "message": "Method and params are required"}}

	match method:
		"get_game_state":
			if not params.is_empty():
				return {"ok": false, "error": {"code": "invalid_arguments", "message": "get_game_state takes no arguments"}}
			return {"ok": true, "result": get_game_state()}
		"set_agent_intent":
			if params.size() != 1 or not params.has("intent") or not (params["intent"] is String):
				return {"ok": false, "error": {"code": "invalid_arguments", "message": "A string intent is required"}}
			var intent_state := set_agent_intent(params["intent"])
			if intent_state.is_empty():
				return {"ok": false, "error": {"code": "invalid_intent", "message": "Intent is not allowed"}}
			return {"ok": true, "result": intent_state}
		_:
			return {"ok": false, "error": {"code": "method_not_found", "message": "Unknown bridge method"}}


func _send_and_close(peer: StreamPeerTCP, response: Dictionary) -> void:
	var payload := (JSON.stringify(response) + "\n").to_utf8_buffer()
	peer.put_data(payload)
	peer.disconnect_from_host()


func _send_error_and_close(peer: StreamPeerTCP, code: String, message: String) -> void:
	_send_and_close(peer, {"ok": false, "error": {"code": code, "message": message}})
