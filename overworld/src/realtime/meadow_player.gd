extends CharacterBody2D
class_name MeadowPlayer

signal attack_started
signal attack_hit(target: MeadowEnemy, damage: int)
signal health_changed(current_health: int, maximum_health: int)
signal damaged(amount: int)
signal defeated

@export var move_speed: float = 190.0
@export var max_health: int = 6
@export var attack_damage: int = 1
@export var attack_reach: float = 52.0
@export var attack_width: float = 20.0
@export var attack_duration: float = 0.14
@export var attack_cooldown: float = 0.34
@export var body_radius: float = 9.0
@export var hurt_iframes: float = 0.55

var facing: Vector2 = Vector2.DOWN
var health: int = 0

var _target: MeadowEnemy
var _attack_active: bool = false
var _attack_elapsed: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _has_hit: bool = false
var _hurt_timer: float = 0.0
var _is_defeated: bool = false


func _ready() -> void:
    add_to_group("meadow_player")
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    health = max_health
    health_changed.emit(health, max_health)
    var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision_shape != null and collision_shape.shape == null:
        var rectangle := RectangleShape2D.new()
        rectangle.size = Vector2(18.0, 18.0)
        collision_shape.shape = rectangle
    queue_redraw()


func _physics_process(delta: float) -> void:
    _attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
    _hurt_timer = maxf(_hurt_timer - delta, 0.0)

    if _is_defeated:
        velocity = Vector2.ZERO
        queue_redraw()
        return

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


func set_enemy_target(target: MeadowEnemy) -> void:
    _target = target


func get_focus_enemy() -> MeadowEnemy:
    var best: MeadowEnemy = null
    var best_score := INF
    for node in get_tree().get_nodes_in_group("meadow_enemy"):
        var enemy := node as MeadowEnemy
        if enemy == null or not enemy.is_alive():
            continue
        var offset := enemy.global_position - global_position
        var distance := offset.length()
        var facing_dot := 1.0 if distance <= 0.001 else facing.dot(offset.normalized())
        var facing_bonus := 0.0 if facing_dot > 0.15 else 180.0
        var score := distance + facing_bonus
        if score < best_score:
            best_score = score
            best = enemy
    return best


func is_attacking() -> bool:
    return _attack_active


func is_alive() -> bool:
    return not _is_defeated


func take_damage(amount: int, direction: Vector2) -> bool:
    if _is_defeated or _hurt_timer > 0.0:
        return false

    var applied := maxi(amount, 1)
    health = maxi(health - applied, 0)
    _hurt_timer = hurt_iframes
    damaged.emit(applied)
    health_changed.emit(health, max_health)

    var knockback := direction.normalized()
    if knockback == Vector2.ZERO:
        knockback = Vector2.DOWN
    velocity = knockback * 160.0

    if health == 0:
        _is_defeated = true
        _attack_active = false
        velocity = Vector2.ZERO
        defeated.emit()

    queue_redraw()
    return true


func get_state() -> Dictionary:
    return {
        "position": global_position,
        "facing": facing,
        "attacking": _attack_active,
        "attack_cooldown": _attack_cooldown_remaining,
        "health": health,
        "max_health": max_health,
        "alive": is_alive(),
    }


func _begin_attack() -> void:
    if _is_defeated or _attack_cooldown_remaining > 0.0:
        return

    _attack_active = true
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = attack_cooldown
    _has_hit = false
    attack_started.emit()
    _try_hit_target()
    queue_redraw()


func _try_hit_target() -> void:
    if _has_hit:
        return

    var best: MeadowEnemy = null
    var best_distance := INF
    for node in get_tree().get_nodes_in_group("meadow_enemy"):
        var enemy := node as MeadowEnemy
        if enemy == null or not enemy.is_alive():
            continue

        var offset := enemy.global_position - global_position
        var distance := offset.length()
        if distance > attack_reach + enemy.body_radius:
            continue

        var target_direction := offset.normalized()
        if target_direction == Vector2.ZERO or facing.dot(target_direction) < 0.2:
            continue

        if distance < best_distance:
            best_distance = distance
            best = enemy

    if best == null:
        return

    if best.take_damage(attack_damage, facing):
        _has_hit = true
        _target = best
        attack_hit.emit(best, attack_damage)


func _draw() -> void:
    draw_rect(Rect2(-12.0, 10.0, 24.0, 7.0), Color(0.08, 0.12, 0.16, 0.28))
    var tunic := Color("#fff1c7") if _hurt_timer > 0.0 else Color("#4c6fff")
    if _is_defeated:
        tunic = Color("#56616b")
    draw_rect(Rect2(-10.0, -10.0, 20.0, 20.0), tunic)
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
