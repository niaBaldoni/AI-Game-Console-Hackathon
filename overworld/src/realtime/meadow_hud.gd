extends CanvasLayer
class_name MeadowHud

var _ui_root: Control
var _message_label: Label
var _heart_row: MeadowHeartRow
var _minimap: MeadowMinimap
var _message_time_remaining: float = 0.0


func _ready() -> void:
	layer = 10
	_build_ui()


func _process(delta: float) -> void:
	if _message_time_remaining <= 0.0:
		return

	_message_time_remaining -= delta
	if _message_time_remaining <= 0.0:
		_message_label.text = ""


func bind_player(player: MeadowPlayer, world_size: Vector2) -> void:
	if _minimap == null:
		return
	_minimap.player = player
	_minimap.world_size = world_size


func set_player_health(current_health: int, maximum_health: int) -> void:
	if _heart_row == null:
		return
	_heart_row.set_health(current_health, maximum_health)


func set_tracked_enemy(_enemy: MeadowEnemy) -> void:
	pass


func set_tracked_enemy_stats(_label_text: String, _current_health: int, _maximum_health: int) -> void:
	pass


func show_message(message: String) -> void:
	if _message_label == null:
		return

	_message_label.text = message
	_message_time_remaining = 1.8


func _build_ui() -> void:
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	_heart_row = MeadowHeartRow.new()
	_heart_row.name = "HeartRow"
	_heart_row.position = Vector2(16.0, 16.0)
	_heart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_heart_row)

	_message_label = _make_label("", Vector2(16.0, 44.0), 16)
	_message_label.add_theme_color_override("font_color", Color("#fff1c7"))

	_minimap = MeadowMinimap.new()
	_minimap.name = "Radar"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.anchor_top = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.anchor_left = 0.0
	_minimap.anchor_right = 0.0
	_minimap.offset_left = 16.0
	_minimap.offset_right = 176.0
	_minimap.offset_top = -176.0
	_minimap.offset_bottom = -16.0
	_minimap.custom_minimum_size = Vector2(160.0, 160.0)
	_ui_root.add_child(_minimap)

	var legend := _make_label("RED MELEE   PURPLE MAGE", Vector2(188.0, 502.0), 12)
	legend.add_theme_color_override("font_color", Color("#d8e7ff"))


func _make_label(value: String, label_position: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = label_position
	label.size = Vector2(420.0, 28.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#ffffff"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(label)
	return label
