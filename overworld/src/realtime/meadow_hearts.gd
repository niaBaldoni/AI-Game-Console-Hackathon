extends Control
class_name MeadowHearts

var lives: int = 3
var max_lives: int = 3


func set_lives(current_lives: int, maximum_lives: int) -> void:
    lives = clampi(current_lives, 0, maximum_lives)
    max_lives = maxi(maximum_lives, 1)
    queue_redraw()


func _draw() -> void:
    var origin := Vector2(8.0, 6.0)
    for index in max_lives:
        _draw_heart(origin + Vector2(index * 38.0, 0.0), index < lives)


func _draw_heart(origin: Vector2, filled: bool) -> void:
    var fill := Color("#e23d4a") if filled else Color("#2b333c")
    var shade := Color("#8f1f32") if filled else Color("#1b2229")
    var outline := Color("#1b1410")
    var cells := [
        Vector2(2, 0), Vector2(3, 0), Vector2(6, 0), Vector2(7, 0),
        Vector2(1, 1), Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1), Vector2(7, 1), Vector2(8, 1),
        Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2), Vector2(7, 2), Vector2(8, 2), Vector2(9, 2),
        Vector2(0, 3), Vector2(1, 3), Vector2(2, 3), Vector2(3, 3), Vector2(4, 3), Vector2(5, 3), Vector2(6, 3), Vector2(7, 3), Vector2(8, 3), Vector2(9, 3),
        Vector2(1, 4), Vector2(2, 4), Vector2(3, 4), Vector2(4, 4), Vector2(5, 4), Vector2(6, 4), Vector2(7, 4), Vector2(8, 4),
        Vector2(2, 5), Vector2(3, 5), Vector2(4, 5), Vector2(5, 5), Vector2(6, 5), Vector2(7, 5),
        Vector2(3, 6), Vector2(4, 6), Vector2(5, 6), Vector2(6, 6),
        Vector2(4, 7), Vector2(5, 7),
    ]
    var pixel := 3.0
    for cell: Vector2 in cells:
        var rect := Rect2(origin + cell * pixel, Vector2(pixel, pixel))
        draw_rect(rect, fill)
        if int(cell.y) >= 5:
            draw_rect(rect, shade)
    draw_rect(Rect2(origin + Vector2(2, 0) * pixel, Vector2(pixel * 2, pixel)), outline, false, 1.0)
    draw_rect(Rect2(origin + Vector2(6, 0) * pixel, Vector2(pixel * 2, pixel)), outline, false, 1.0)
