extends CanvasLayer
class_name MeadowHud

var _ui_root: Control
var _message_label: Label
var _target_label: Label
var _player_label: Label
var _health_fill: ColorRect
var _hearts: MeadowHearts
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
	if _player_label != null:
		_player_label.text = "LIVES"
	if _hearts != null:
		_hearts.set_lives(current_health, maximum_health)


func set_tracked_enemy(_enemy: MeadowEnemy) -> void:
	pass


func set_tracked_enemy_stats(_label_text: String, _current_health: int, _maximum_health: int) -> void:
	pass


func set_enemy_health(current_health: int, maximum_health: int) -> void:
	set_tracked_enemy_stats("TARGET", current_health, maximum_health)


func set_enemy_count(current_count: int, maximum_count: int) -> void:
	if _target_label == null:
		return

	_target_label.text = "ENEMIES  %d / %d" % [current_count, maximum_count]


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

	_hearts = MeadowHearts.new()
	_hearts.name = "Hearts"
	_hearts.position = Vector2(16.0, 16.0)
	_hearts.size = Vector2(220.0, 36.0)
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hearts.set_lives(5, 5)
	_ui_root.add_child(_hearts)

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

	var legend := _make_label("RED BRUTE  PURPLE MAGE  PINK HEART  GOLD POWER  BLUE SHIELD", Vector2(188.0, 502.0), 11)
	legend.size = Vector2(760.0, 28.0)
	legend.add_theme_color_override("font_color", Color("#d8e7ff"))


func _make_label(value: String, label_position: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = label_position
	label.size = Vector2(420.0, 28.0)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Press Start 2P", "Monaco", "Menlo", "Courier New", "monospace"])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#ffffff"))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 1.0))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(label)
	return label
