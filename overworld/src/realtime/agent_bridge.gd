extends Node
class_name RuntimeAgentBridge

## Bridge between a running Summer/Godot game and runtime-mcp/server.py.
## Desktop uses loopback TCP; the Uno Q App Lab runner uses the shared app mount.
## Add this script as an Autoload named "AgentBridge" in the game project.

signal agent_intent_changed(intent: String)
signal enemy_spawn_requested(request_id: int, position: Vector2, health: int, kind_name: String, override_health: bool)

@export var listen_host: String = "127.0.0.1"
@export var listen_port: int = 8765

const MAX_MESSAGE_BYTES := 64 * 1024
const ALLOWED_INTENTS := ["idle", "left", "right", "act"]
const MEADOW_X_MIN := 24.0
const MEADOW_X_MAX := 2376.0
const MEADOW_Y_MIN := 24.0
const MEADOW_Y_MAX := 1326.0
const DEFAULT_ENEMY_HEALTH := 3
const MIN_ENEMY_HEALTH := 1
const MAX_ENEMY_HEALTH := 9

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _agent_intent := "idle"
var _revision := 0
var _summary: Dictionary = {}
var _next_spawn_request_id := 1
var _spawn_resolutions: Dictionary = {}
var _file_bridge_dir: String = ""


func _ready() -> void:
	_file_bridge_dir = ProjectSettings.globalize_path("res://.runtime-mcp")
	if DirAccess.make_dir_recursive_absolute(_file_bridge_dir) == OK:
		_clear_file_bridge_files()
	else:
		_file_bridge_dir = ""

	var error := _server.listen(listen_port, listen_host)
	if error != OK and _file_bridge_dir.is_empty():
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
	_process_file_requests()

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


func _process_file_requests() -> void:
	if _file_bridge_dir.is_empty():
		return

	var directory := DirAccess.open(_file_bridge_dir)
	if directory == null:
		return

	directory.list_dir_begin()
	var processed := 0
	var file_name := directory.get_next()
	while not file_name.is_empty() and processed < 8:
		if not directory.current_is_dir() and file_name.begins_with("request-") and file_name.ends_with(".json"):
			var request_id := file_name.trim_prefix("request-").trim_suffix(".json")
			if _valid_file_request_id(request_id):
				var request_path := _file_bridge_dir.path_join(file_name)
				var request_line := FileAccess.get_file_as_string(request_path)
				var response := _handle_request(request_line)
				_write_file_response(request_id, response)
				DirAccess.remove_absolute(request_path)
				processed += 1
		file_name = directory.get_next()
	directory.list_dir_end()


func _valid_file_request_id(request_id: String) -> bool:
	return not request_id.is_empty() and request_id.length() <= 64 and not request_id.contains("/") and not request_id.contains("\\") and not request_id.contains("..")


func _write_file_response(request_id: String, response: Dictionary) -> void:
	var response_path := _file_bridge_dir.path_join("response-%s.json" % request_id)
	var temporary_path := _file_bridge_dir.path_join(".response-%s.tmp" % request_id)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	var response_with_id := response.duplicate(true)
	response_with_id["id"] = request_id
	file.store_string(JSON.stringify(response_with_id))
	file.close()
	DirAccess.rename_absolute(temporary_path, response_path)


func _clear_file_bridge_files() -> void:
	if _file_bridge_dir.is_empty():
		return
	var directory := DirAccess.open(_file_bridge_dir)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.begins_with("request-") or file_name.begins_with("response-") or file_name.begins_with(".response-")):
			DirAccess.remove_absolute(_file_bridge_dir.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()


func publish_summary(summary: Dictionary) -> void:
	## Called by game logic to publish a small, JSON-safe observation.
	if summary != _summary:
		_revision += 1
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


func request_enemy_spawn(params: Dictionary) -> Dictionary:
	if params.size() < 2 or params.size() > 4 or not params.has("x") or not params.has("y"):
		return {}
	for key in params.keys():
		if key not in ["x", "y", "health", "kind"]:
			return {}

	var x_value = params["x"]
	var y_value = params["y"]
	if not _is_number(x_value) or not _is_number(y_value):
		return {}

	var position := Vector2(float(x_value), float(y_value))
	if position.x < MEADOW_X_MIN or position.x > MEADOW_X_MAX:
		return {}
	if position.y < MEADOW_Y_MIN or position.y > MEADOW_Y_MAX:
		return {}

	var kind_name := "brute"
	if params.has("kind"):
		kind_name = _normalize_kind_name(params["kind"])
		if kind_name.is_empty():
			return {}

	var override_health := params.has("health")
	var health := DEFAULT_ENEMY_HEALTH
	if override_health:
		if not _is_integer_number(params["health"]):
			return {}
		health = int(params["health"])
		if health < MIN_ENEMY_HEALTH or health > MAX_ENEMY_HEALTH:
			return {}

	var request_id := _next_spawn_request_id
	_next_spawn_request_id += 1
	enemy_spawn_requested.emit(request_id, position, health, kind_name, override_health)
	var default_result := {
		"queued": true,
		"request_id": request_id,
		"position": position,
		"health": health,
		"kind": kind_name,
	}
	var resolved_result: Dictionary = _spawn_resolutions.get(request_id, default_result)
	_spawn_resolutions.erase(request_id)
	return resolved_result


func _normalize_kind_name(value: Variant) -> String:
	if not (value is String):
		return ""
	var key := String(value).strip_edges().to_lower()
	if key == "melee" or key == "brute":
		return "brute"
	if key == "mage" or key == "ranged":
		return "mage"
	return ""


func resolve_spawn_request(request_id: int, result: Dictionary) -> void:
	_spawn_resolutions[request_id] = result


func _is_number(value: Variant) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	var number := float(value)
	return number == number and number > -INF and number < INF


func _is_integer_number(value: Variant) -> bool:
	if not _is_number(value):
		return false
	var number := float(value)
	return floorf(number) == number


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
		"spawn_enemy":
			var spawn_state := request_enemy_spawn(params)
			if spawn_state.is_empty():
				return {"ok": false, "error": {"code": "invalid_spawn", "message": "Spawn position, kind, or health is not allowed"}}
			if spawn_state.get("accepted", true) == false:
				return {
					"ok": false,
					"error": {
						"code": str(spawn_state.get("error_code", "spawn_rejected")),
						"message": str(spawn_state.get("error_message", "The game rejected the spawn")),
					},
				}
			return {"ok": true, "result": spawn_state}
		_:
			return {"ok": false, "error": {"code": "method_not_found", "message": "Unknown bridge method"}}


func _send_and_close(peer: StreamPeerTCP, response: Dictionary) -> void:
	var payload := (JSON.stringify(response) + "\n").to_utf8_buffer()
	peer.put_data(payload)
	peer.disconnect_from_host()


func _send_error_and_close(peer: StreamPeerTCP, code: String, message: String) -> void:
	_send_and_close(peer, {"ok": false, "error": {"code": code, "message": message}})
