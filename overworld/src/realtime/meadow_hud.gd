extends CanvasLayer
class_name MeadowHud

var _ui_root: Control
var _target_label: Label
var _player_label: Label
var _message_label: Label
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


func set_tracked_enemy(enemy: MeadowEnemy) -> void:
    if enemy == null or not enemy.is_alive():
        set_tracked_enemy_stats("NO TARGET", 0, 1)
        return
    set_tracked_enemy_stats(enemy.get_difficulty_name(), enemy.health, enemy.max_health)


func set_tracked_enemy_stats(label_text: String, current_health: int, maximum_health: int) -> void:
    if _target_label == null:
        return

    _target_label.text = "%s  %d / %d" % [label_text, current_health, maximum_health]
    var health_ratio := clampf(float(current_health) / float(maxi(maximum_health, 1)), 0.0, 1.0)
    _health_fill.size.x = 180.0 * health_ratio


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
    _hearts.position = Vector2(414.0, 10.0)
    _hearts.size = Vector2(132.0, 34.0)
    _hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hearts.set_lives(3, 3)
    _ui_root.add_child(_hearts)

    var panel := ColorRect.new()
    panel.position = Vector2(16.0, 16.0)
    panel.size = Vector2(270.0, 132.0)
    panel.color = Color(0.08, 0.12, 0.16, 0.88)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui_root.add_child(panel)

    var title := _make_label("OPEN MEADOW", Vector2(16.0, 10.0), 18)
    title.add_theme_color_override("font_color", Color("#f2c14e"))

    var controls := _make_label("JOYSTICK MOVE   A SWING   B PAUSE", Vector2(16.0, 38.0), 14)
    controls.add_theme_color_override("font_color", Color("#d8e7ff"))

    _player_label = _make_label("LIVES", Vector2(16.0, 60.0), 14)
    _player_label.add_theme_color_override("font_color", Color("#ff8b96"))

    _target_label = _make_label("BRUTE  3 / 3", Vector2(16.0, 82.0), 14)
    _target_label.add_theme_color_override("font_color", Color("#fff1c7"))

    var health_back := ColorRect.new()
    health_back.position = Vector2(16.0, 106.0)
    health_back.size = Vector2(180.0, 6.0)
    health_back.color = Color("#263238")
    health_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(health_back)

    _health_fill = ColorRect.new()
    _health_fill.position = health_back.position
    _health_fill.size = Vector2(180.0, 6.0)
    _health_fill.color = Color("#f2c14e")
    _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(_health_fill)

    _message_label = _make_label("", Vector2(16.0, 148.0), 16)
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

    var legend := _make_label("RED BRUTE   PURPLE MAGE   HOLD A SPIN", Vector2(188.0, 502.0), 12)
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
