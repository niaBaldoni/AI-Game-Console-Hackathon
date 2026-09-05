extends CharacterBody2D
class_name MeadowEnemy

signal health_changed(current_health: int, maximum_health: int)
signal defeated
signal hit_landed(damage: int)

@export var max_health: int = 3
@export var knockback_speed: float = 145.0
@export var knockback_duration: float = 0.16
@export var body_radius: float = 13.0

var health: int = 0
var runtime_id: int = 0
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0
var _hurt_timer: float = 0.0
var _is_defeated: bool = false


func _ready() -> void:
    add_to_group("meadow_enemy")
    var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision_shape == null:
        collision_shape = CollisionShape2D.new()
        collision_shape.name = "CollisionShape2D"
        add_child(collision_shape)
    if collision_shape.shape == null:
        var rectangle := RectangleShape2D.new()
        rectangle.size = Vector2(body_radius * 2.0, body_radius * 2.0)
        collision_shape.shape = rectangle
    health = max_health
    health_changed.emit(health, max_health)
    queue_redraw()


func _physics_process(delta: float) -> void:
    if _is_defeated:
        return

    if _knockback_timer > 0.0:
        velocity = _knockback_velocity
        move_and_slide()
        _knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 950.0 * delta)
        _knockback_timer -= delta
    else:
        velocity = Vector2.ZERO

    _hurt_timer = maxf(_hurt_timer - delta, 0.0)
    queue_redraw()


func is_alive() -> bool:
    return not _is_defeated


func take_damage(amount: int, direction: Vector2) -> bool:
    if _is_defeated:
        return false

    var applied_damage := maxi(amount, 1)
    health = maxi(health - applied_damage, 0)
    _hurt_timer = 0.14

    var knockback_direction := direction.normalized()
    if knockback_direction == Vector2.ZERO:
        knockback_direction = Vector2.DOWN
    _knockback_velocity = knockback_direction * knockback_speed
    _knockback_timer = knockback_duration

    hit_landed.emit(applied_damage)
    health_changed.emit(health, max_health)

    if health == 0:
        _is_defeated = true
        velocity = Vector2.ZERO
        defeated.emit()

    queue_redraw()
    return true


func get_state() -> Dictionary:
    return {
        "id": runtime_id,
        "health": health,
        "max_health": max_health,
        "alive": is_alive(),
        "position": global_position,
    }


func _draw() -> void:
    var body_color := Color("#d95763")
    if _hurt_timer > 0.0:
        body_color = Color("#fff1c7")

    draw_rect(Rect2(-16.0, 10.0, 32.0, 7.0), Color(0.08, 0.12, 0.16, 0.28))
    if _is_defeated:
        draw_circle(Vector2.ZERO, body_radius, Color("#56616b"))
        draw_line(Vector2(-7.0, -7.0), Vector2(7.0, 7.0), Color("#202b36"), 3.0)
        draw_line(Vector2(7.0, -7.0), Vector2(-7.0, 7.0), Color("#202b36"), 3.0)
    else:
        draw_circle(Vector2.ZERO, body_radius, body_color)
        draw_rect(Rect2(-10.0, -5.0, 6.0, 4.0), Color("#fff1c7"))
        draw_rect(Rect2(4.0, -5.0, 6.0, 4.0), Color("#fff1c7"))
        draw_rect(Rect2(-8.0, 3.0, 16.0, 4.0), Color("#8f3548"))

    var health_ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
    draw_rect(Rect2(-20.0, -28.0, 40.0, 5.0), Color("#263238"))
    draw_rect(Rect2(-20.0, -28.0, 40.0 * health_ratio, 5.0), Color("#f2c14e"))
