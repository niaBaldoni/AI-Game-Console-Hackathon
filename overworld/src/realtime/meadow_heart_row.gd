extends Control
class_name MeadowHeartRow

const HEART_SIZE := 20.0
const HEART_SPACING := 24.0
const FILLED_COLOR := Color("#e6435c")
const EMPTY_COLOR := Color("#37414d")
const OUTLINE_COLOR := Color("#1b2128")

var _current_health: int = 0
var _max_health: int = 0


func set_health(current_health: int, maximum_health: int) -> void:
	_max_health = maxi(maximum_health, 0)
	_current_health = clampi(current_health, 0, _max_health)
	custom_minimum_size = Vector2(maxf(_max_health * HEART_SPACING - (HEART_SPACING - HEART_SIZE), 0.0), HEART_SIZE)
	queue_redraw()


func _draw() -> void:
	for i in range(_max_health):
		var center := Vector2(i * HEART_SPACING + HEART_SIZE * 0.5, HEART_SIZE * 0.5)
		_draw_heart(center, HEART_SIZE, i < _current_health)


func _draw_heart(center: Vector2, size: float, filled: bool) -> void:
	var fill_color := FILLED_COLOR if filled else EMPTY_COLOR
	var lobe_radius := size * 0.28
	var left_center := center + Vector2(-lobe_radius, -lobe_radius * 0.65)
	var right_center := center + Vector2(lobe_radius, -lobe_radius * 0.65)
	var points := PackedVector2Array([
		center + Vector2(-size * 0.5, -size * 0.05),
		center + Vector2(size * 0.5, -size * 0.05),
		center + Vector2(0.0, size * 0.55),
	])

	draw_circle(left_center, lobe_radius, fill_color)
	draw_circle(right_center, lobe_radius, fill_color)
	draw_colored_polygon(points, fill_color)

	if not filled:
		draw_circle(left_center, lobe_radius, OUTLINE_COLOR, false, 1.5)
		draw_circle(right_center, lobe_radius, OUTLINE_COLOR, false, 1.5)
		var outline_points := points.duplicate()
		outline_points.append(points[0])
		draw_polyline(outline_points, OUTLINE_COLOR, 1.5)
