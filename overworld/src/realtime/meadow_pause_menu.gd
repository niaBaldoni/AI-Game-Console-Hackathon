extends CanvasLayer
class_name MeadowPauseMenu

signal play_selected
signal back_selected
signal restart_selected
signal quit_selected

enum Mode { TITLE, PAUSED, DEFEATED, VICTORY }

## Set true before reload_current_scene() to skip the title and drop into play.
static var start_in_game: bool = false

const PANEL_SIZE := Vector2(420.0, 380.0)
const GOLD := Color("#f2c14e")
const INK := Color(0.08, 0.12, 0.16, 0.94)
const MIST := Color("#d8e7ff")

var _mode: Mode = Mode.TITLE
var _is_open: bool = false
var _ignore_pause_frames: int = 0
var _title_label: Label
var _subtitle_label: Label
var _hint_label: Label
var _tutorial_label: Label
var _primary_button: Button
var _restart_button: Button
var _quit_button: Button


func _ready() -> void:
    layer = 30
    process_mode = Node.PROCESS_MODE_ALWAYS
    _ensure_pause_bindings()
    _build_ui()
    visible = false


func _process(_delta: float) -> void:
    if _ignore_pause_frames > 0:
        _ignore_pause_frames -= 1


func _unhandled_input(event: InputEvent) -> void:
    if event.is_echo():
        return
    if not event.is_action_pressed("pause") and not event.is_action_pressed("ui_cancel"):
        return

    var viewport := get_viewport()
    if viewport != null:
        viewport.set_input_as_handled()
    if _ignore_pause_frames > 0:
        return

    if _is_open:
        match _mode:
            Mode.TITLE:
                pass
            Mode.DEFEATED:
                back_selected.emit()
            Mode.PAUSED:
                close_menu()
                play_selected.emit()
            Mode.VICTORY:
                back_selected.emit()
    else:
        _open_from_gameplay()


func is_open() -> bool:
    return _is_open


func open_title() -> void:
    _mode = Mode.TITLE
    _show_menu()


func open_paused() -> void:
    _mode = Mode.PAUSED
    _show_menu()


func open_defeated() -> void:
    _mode = Mode.DEFEATED
    _show_menu()


func open_victory() -> void:
    _mode = Mode.VICTORY
    _show_menu()


func close_menu() -> void:
    _is_open = false
    visible = false
    get_tree().paused = false
    _ignore_pause_frames = 2


func _open_from_gameplay() -> void:
    var meadow_player := get_tree().get_first_node_in_group("meadow_player") as MeadowPlayer
    if meadow_player != null and not meadow_player.is_alive():
        open_defeated()
        return
    open_paused()


func _show_menu() -> void:
    _is_open = true
    visible = true
    get_tree().paused = true
    _ignore_pause_frames = 2
    _refresh_copy()
    _focus_primary.call_deferred()


func _refresh_copy() -> void:
    match _mode:
        Mode.TITLE:
            _title_label.text = "OPEN MEADOW"
            _subtitle_label.text = "Five hearts. Find more in the wild."
            _primary_button.text = "PLAY"
            _restart_button.visible = false
            _hint_label.text = "JOYSTICK SELECT    A CONFIRM"
            _tutorial_label.visible = true
            _tutorial_label.text = "JOYSTICK WALK\nA TAP SWING  HOLD A SPIN\nB PAUSE\nPINK HEARTS HEAL  GOLD STARS HIT HARDER  BLUE RINGS SHIELD"
        Mode.DEFEATED:
            _title_label.text = "YOU FELL"
            _subtitle_label.text = "Walk back, or take another swing."
            _primary_button.text = "BACK"
            _restart_button.visible = true
            _restart_button.text = "RESTART"
            _hint_label.text = "JOYSTICK SELECT    A CONFIRM    B BACK"
            _tutorial_label.visible = false
        Mode.VICTORY:
            _title_label.text = "MEADOW CLEARED"
            _subtitle_label.text = "25 enemies defeated. The meadow is safe."
            _primary_button.text = "PLAY AGAIN"
            _restart_button.visible = false
            _hint_label.text = "JOYSTICK SELECT    A RESTART    B TITLE"
            _tutorial_label.visible = false
        Mode.PAUSED:
            _title_label.text = "PAUSED"
            _subtitle_label.text = "Roads still. Radar holds north."
            _primary_button.text = "PLAY"
            _restart_button.visible = true
            _restart_button.text = "RESTART"
            _hint_label.text = "JOYSTICK SELECT    A CONFIRM    B PLAY"
            _tutorial_label.visible = false
    _refresh_focus_neighbors()


func _refresh_focus_neighbors() -> void:
    if _restart_button.visible:
        _primary_button.focus_neighbor_bottom = _restart_button.get_path()
        _restart_button.focus_neighbor_top = _primary_button.get_path()
        _restart_button.focus_neighbor_bottom = _quit_button.get_path()
        _quit_button.focus_neighbor_top = _restart_button.get_path()
    else:
        _primary_button.focus_neighbor_bottom = _quit_button.get_path()
        _quit_button.focus_neighbor_top = _primary_button.get_path()


func _focus_primary() -> void:
    if _primary_button != null:
        _primary_button.grab_focus()


func _on_primary_pressed() -> void:
    match _mode:
        Mode.DEFEATED:
            back_selected.emit()
        Mode.VICTORY:
            restart_selected.emit()
        Mode.TITLE, Mode.PAUSED:
            close_menu()
            play_selected.emit()


func _on_restart_pressed() -> void:
    restart_selected.emit()


func _on_quit_pressed() -> void:
    quit_selected.emit()


func _ensure_pause_bindings() -> void:
    if not InputMap.has_action("pause"):
        InputMap.add_action("pause")
    _bind_key("pause", KEY_K)
    _bind_key("pause", KEY_L)
    _bind_key("ui_cancel", KEY_K)


func _bind_key(action_name: String, keycode: Key) -> void:
    for existing in InputMap.action_get_events(action_name):
        var existing_key := existing as InputEventKey
        if existing_key != null and existing_key.physical_keycode == keycode:
            return
    var event := InputEventKey.new()
    event.physical_keycode = keycode
    InputMap.action_add_event(action_name, event)


func _build_ui() -> void:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    var dim := ColorRect.new()
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.04, 0.09, 0.06, 0.72)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(dim)
    var scan := ColorRect.new()
    scan.set_anchors_preset(Control.PRESET_FULL_RECT)
    scan.color = Color(0.02, 0.04, 0.03, 0.18)
    scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(scan)

    var panel := Panel.new()
    panel.position = Vector2(270.0, 111.0)
    panel.size = PANEL_SIZE
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _panel_style())
    root.add_child(panel)

    var accent := ColorRect.new()
    accent.position = Vector2(18.0, 18.0)
    accent.size = Vector2(8.0, 344.0)
    accent.color = GOLD
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(accent)

    _title_label = _make_label(panel, "OPEN MEADOW", Vector2(40.0, 14.0), 28, GOLD)
    _subtitle_label = _make_label(panel, "Five hearts. Find more in the wild.", Vector2(40.0, 48.0), 14, MIST)

    _tutorial_label = _make_label(panel, "", Vector2(40.0, 74.0), 13, Color("#fff1c7"))
    _tutorial_label.size = Vector2(340.0, 72.0)
    _tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    _primary_button = _make_button(panel, "PLAY", Vector2(40.0, 158.0), _on_primary_pressed)
    _restart_button = _make_button(panel, "RESTART", Vector2(40.0, 208.0), _on_restart_pressed)
    _quit_button = _make_button(panel, "QUIT", Vector2(40.0, 258.0), _on_quit_pressed)

    _hint_label = _make_label(
        panel,
        "JOYSTICK SELECT    A CONFIRM",
        Vector2(40.0, 318.0),
        13,
        Color("#fff1c7")
    )
    _hint_label.size = Vector2(360.0, 28.0)
    panel.position = Vector2(270.0, 80.0)
    _refresh_focus_neighbors()


func _make_label(parent: Control, text: String, label_position: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.position = label_position
    label.size = Vector2(360.0, 32.0)
    var font := _retro_font()
    if font != null:
        label.add_theme_font_override("font", font)
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 1.0))
    label.add_theme_constant_override("outline_size", 4)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label


func _make_button(parent: Control, text: String, button_position: Vector2, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.position = button_position
    button.size = Vector2(340.0, 42.0)
    button.focus_mode = Control.FOCUS_ALL
    var font := _retro_font()
    if font != null:
        button.add_theme_font_override("font", font)
    button.add_theme_font_size_override("font_size", 16)
    button.add_theme_color_override("font_color", MIST)
    button.add_theme_color_override("font_hover_color", Color("#1b2430"))
    button.add_theme_color_override("font_focus_color", Color("#1b2430"))
    button.add_theme_color_override("font_pressed_color", Color("#1b2430"))
    button.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 1.0))
    button.add_theme_constant_override("outline_size", 3)
    button.add_theme_stylebox_override("normal", _button_style(INK, Color("#5b8f52")))
    button.add_theme_stylebox_override("hover", _button_style(GOLD, GOLD))
    button.add_theme_stylebox_override("focus", _button_style(GOLD, GOLD))
    button.add_theme_stylebox_override("pressed", _button_style(Color("#c9a227"), GOLD))
    button.pressed.connect(callback)
    parent.add_child(button)
    return button


func _retro_font() -> Font:
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["Press Start 2P", "Monaco", "Menlo", "Courier New", "monospace"])
    font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
    return font


func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = INK
    style.border_color = GOLD
    style.set_border_width_all(3)
    style.set_corner_radius_all(4)
    style.content_margin_left = 8
    style.content_margin_right = 8
    return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(2)
    style.set_corner_radius_all(3)
    style.content_margin_left = 16
    style.content_margin_right = 16
    return style
