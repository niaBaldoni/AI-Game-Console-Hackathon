extends CharacterBody2D
class_name MeadowPlayer

signal attack_started
signal attack_hit(target: MeadowEnemy, damage: int)

@export var move_speed: float = 190.0
@export var attack_damage: int = 1
@export var attack_reach: float = 52.0
@export var attack_width: float = 20.0
@export var attack_duration: float = 0.14
@export var attack_cooldown: float = 0.34

var facing: Vector2 = Vector2.DOWN

var _attack_active: bool = false
var _attack_elapsed: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _hit_targets: Array[MeadowEnemy] = []


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision_shape != null and collision_shape.shape == null:
        var rectangle := RectangleShape2D.new()
        rectangle.size = Vector2(18.0, 18.0)
        collision_shape.shape = rectangle
    queue_redraw()


func _physics_process(delta: float) -> void:
    _attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

    var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if input_vector.length_squared() > 0.01:
        facing = input_vector.normalized()
        velocity = input_vector * move_speed
    else:
        velocity = Vector2.ZERO
    move_and_slide()

    if Input.is_action_just_pressed("attack"):
        _begin_attack()

    if _attack_active:
        _attack_elapsed += delta
        _try_hit_target()
        if _attack_elapsed >= attack_duration:
            _attack_active = false

    queue_redraw()


func is_attacking() -> bool:
    return _attack_active


func get_state() -> Dictionary:
    return {
        "position": global_position,
        "facing": facing,
        "attacking": _attack_active,
        "attack_cooldown": _attack_cooldown_remaining,
    }


func _begin_attack() -> void:
    if _attack_cooldown_remaining > 0.0:
        return

    _attack_active = true
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = attack_cooldown
    _hit_targets.clear()
    attack_started.emit()
    _try_hit_target()
    queue_redraw()


func _try_hit_target() -> void:
    for candidate in get_tree().get_nodes_in_group("meadow_enemy"):
        var target := candidate as MeadowEnemy
        if target == null or _hit_targets.has(target) or not target.is_alive():
            continue

        var offset := target.global_position - global_position
        var distance := offset.length()
        if distance > attack_reach + target.body_radius:
            continue

        var target_direction := offset.normalized()
        if target_direction == Vector2.ZERO or facing.dot(target_direction) < 0.2:
            continue

        if target.take_damage(attack_damage, facing):
            _hit_targets.append(target)
            attack_hit.emit(target, attack_damage)


func _draw() -> void:
    draw_rect(Rect2(-12.0, 10.0, 24.0, 7.0), Color(0.08, 0.12, 0.16, 0.28))
    draw_rect(Rect2(-10.0, -10.0, 20.0, 20.0), Color("#4c6fff"))
    draw_rect(Rect2(-7.0, -8.0, 14.0, 7.0), Color("#f0c27b"))
    draw_rect(Rect2(-5.0, -5.0, 3.0, 3.0), Color("#28324a"))
    draw_rect(Rect2(2.0, -5.0, 3.0, 3.0), Color("#28324a"))
    draw_line(Vector2.ZERO, facing * 13.0, Color("#d8e7ff"), 3.0)

    if _attack_active:
        var side := Vector2(-facing.y, facing.x)
        var origin := facing * 9.0
        var tip := facing * attack_reach
        var points := PackedVector2Array([
            origin - side * (attack_width * 0.5),
            tip,
            origin + side * (attack_width * 0.5),
        ])
        draw_colored_polygon(points, Color(0.95, 0.88, 0.55, 0.9))
        draw_polyline(
            PackedVector2Array([points[0], points[1], points[2], points[0]]),
            Color("#fff8d6"),
            3.0,
            false
        )
