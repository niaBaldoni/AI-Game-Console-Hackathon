extends CharacterBody2D
class_name MeadowEnemy

signal health_changed(current_health: int, maximum_health: int)
signal defeated
signal hit_landed(damage: int)

enum Difficulty { SCOUT, HUNTER, BRUTE }

const DIFFICULTY_NAMES := {
    Difficulty.SCOUT: "SCOUT",
    Difficulty.HUNTER: "HUNTER",
    Difficulty.BRUTE: "BRUTE",
}

@export var max_health: int = 3
@export var knockback_speed: float = 145.0
@export var knockback_duration: float = 0.16
@export var body_radius: float = 13.0
@export var difficulty: Difficulty = Difficulty.SCOUT

var health: int = 0
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0
var _hurt_timer: float = 0.0
var _is_defeated: bool = false
var _body_color: Color = Color("#d95763")


func _ready() -> void:
    add_to_group("meadow_enemy")
    apply_difficulty(difficulty)
    queue_redraw()


func apply_difficulty(level: Difficulty) -> void:
    difficulty = level
    match difficulty:
        Difficulty.SCOUT:
            max_health = 2
            body_radius = 13.0
            knockback_speed = 180.0
            _body_color = Color("#d95763")
        Difficulty.HUNTER:
            max_health = 4
            body_radius = 22.0
            knockback_speed = 130.0
            _body_color = Color("#e0893a")
        Difficulty.BRUTE:
            max_health = 7
            body_radius = 34.0
            knockback_speed = 90.0
            _body_color = Color("#8f2438")

    health = max_health
    _is_defeated = false
    _sync_collision()
    health_changed.emit(health, max_health)
    queue_redraw()


func _sync_collision() -> void:
    var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision == null:
        return
    var rectangle := RectangleShape2D.new()
    rectangle.size = Vector2(body_radius * 1.7, body_radius * 1.7)
    collision.shape = rectangle



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
        "health": health,
        "max_health": max_health,
        "alive": is_alive(),
        "position": global_position,
        "difficulty": difficulty,
        "difficulty_name": get_difficulty_name(),
    }


func get_difficulty_name() -> String:
    return str(DIFFICULTY_NAMES.get(difficulty, "SCOUT"))


func get_radar_color() -> Color:
    match difficulty:
        Difficulty.HUNTER:
            return Color("#ffd35c")
        Difficulty.BRUTE:
            return Color("#ff5b5b")
        _:
            return Color("#7dff8a")


func get_radar_blip_radius() -> float:
    match difficulty:
        Difficulty.HUNTER:
            return 5.5
        Difficulty.BRUTE:
            return 7.5
        _:
            return 3.8


func _draw() -> void:
    var body_color := _body_color
    if _hurt_timer > 0.0:
        body_color = Color("#fff1c7")

    var shadow_width := body_radius * 2.4
    draw_rect(Rect2(-shadow_width * 0.5, body_radius * 0.75, shadow_width, body_radius * 0.45), Color(0.08, 0.12, 0.16, 0.28))
    if _is_defeated:
        draw_circle(Vector2.ZERO, body_radius, Color("#56616b"))
        draw_line(Vector2(-body_radius * 0.5, -body_radius * 0.5), Vector2(body_radius * 0.5, body_radius * 0.5), Color("#202b36"), 3.0)
        draw_line(Vector2(body_radius * 0.5, -body_radius * 0.5), Vector2(-body_radius * 0.5, body_radius * 0.5), Color("#202b36"), 3.0)
    else:
        draw_circle(Vector2.ZERO, body_radius, body_color)
        var eye_w := maxf(body_radius * 0.28, 4.0)
        var eye_h := maxf(body_radius * 0.18, 3.0)
        draw_rect(Rect2(-body_radius * 0.55, -body_radius * 0.28, eye_w, eye_h), Color("#fff1c7"))
        draw_rect(Rect2(body_radius * 0.22, -body_radius * 0.28, eye_w, eye_h), Color("#fff1c7"))
        draw_rect(Rect2(-body_radius * 0.45, body_radius * 0.18, body_radius * 0.9, body_radius * 0.22), Color("#8f3548"))
        if difficulty == Difficulty.BRUTE:
            draw_circle(Vector2(-body_radius * 0.7, -body_radius * 0.55), 5.0, Color("#5a1422"))
            draw_circle(Vector2(body_radius * 0.7, -body_radius * 0.55), 5.0, Color("#5a1422"))
        elif difficulty == Difficulty.HUNTER:
            draw_circle(Vector2(0.0, -body_radius * 0.15), 3.0, Color("#7a3a12"))

    var health_ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
    var bar_width := body_radius * 2.4
    draw_rect(Rect2(-bar_width * 0.5, -body_radius - 15.0, bar_width, 5.0), Color("#263238"))
    draw_rect(Rect2(-bar_width * 0.5, -body_radius - 15.0, bar_width * health_ratio, 5.0), Color("#f2c14e"))
