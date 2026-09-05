extends Area2D
class_name MeadowPickup

enum Kind { HEART, POWER, SHIELD }

signal collected(kind: Kind)

@export var kind: Kind = Kind.HEART

var _phase: float = 0.0
var _taken: bool = false


func _ready() -> void:
    add_to_group("meadow_pickup")
    monitoring = true
    monitorable = false
    collision_layer = 0
    collision_mask = 1
    body_entered.connect(_on_body_entered)
    if get_node_or_null("CollisionShape2D") == null:
        var collision := CollisionShape2D.new()
        var circle := CircleShape2D.new()
        circle.radius = 12.0
        collision.shape = circle
        add_child(collision)
    _phase = randf() * TAU
    queue_redraw()


func _process(delta: float) -> void:
    _phase += delta * 3.2
    queue_redraw()


func get_radar_color() -> Color:
    match kind:
        Kind.POWER:
            return Color("#ffd35c")
        Kind.SHIELD:
            return Color("#7ee0ff")
        _:
            return Color("#ff6b7a")


func _on_body_entered(body: Node2D) -> void:
    if _taken:
        return
    var meadow_player := body as MeadowPlayer
    if meadow_player == null or not meadow_player.is_alive():
        return
    _taken = true
    match kind:
        Kind.HEART:
            meadow_player.collect_heart()
        Kind.POWER:
            meadow_player.grant_power(9.0)
        Kind.SHIELD:
            meadow_player.grant_shield(7.0)
    collected.emit(kind)
    queue_free()


func _draw() -> void:
    var bob := sin(_phase) * 2.0
    var glow := 0.18 + 0.08 * sin(_phase * 1.7)
    match kind:
        Kind.POWER:
            draw_circle(Vector2(0.0, bob + 8.0), 9.0, Color(0.95, 0.7, 0.15, glow))
            draw_circle(Vector2(0.0, bob), 8.0, Color("#f2c14e"))
            draw_circle(Vector2(0.0, bob), 3.0, Color("#fff8d6"))
        Kind.SHIELD:
            draw_circle(Vector2(0.0, bob + 8.0), 9.0, Color(0.4, 0.85, 1.0, glow))
            draw_arc(Vector2(0.0, bob), 8.0, 0.0, TAU, 16, Color("#7ee0ff"), 3.0, true)
            draw_circle(Vector2(0.0, bob), 4.0, Color("#d8f7ff"))
        Kind.HEART:
            draw_circle(Vector2(0.0, bob + 8.0), 8.0, Color(0.8, 0.15, 0.2, glow))
            _draw_mini_heart(Vector2(0.0, bob))


func _draw_mini_heart(origin: Vector2) -> void:
    var fill := Color("#e23d4a")
    draw_circle(origin + Vector2(-3.5, -1.5), 3.6, fill)
    draw_circle(origin + Vector2(3.5, -1.5), 3.6, fill)
    var points := PackedVector2Array([
        origin + Vector2(-6.5, 0.0),
        origin + Vector2(0.0, 7.5),
        origin + Vector2(6.5, 0.0),
    ])
    draw_colored_polygon(points, fill)
