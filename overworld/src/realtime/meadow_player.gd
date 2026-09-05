extends CharacterBody2D
class_name MeadowPlayer

signal attack_started
signal spin_charge_started
signal spin_attack_started
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
@export var spin_charge_threshold: float = 0.25
@export var spin_move_speed_multiplier: float = 0.45
@export var spin_attack_damage: int = 2
@export var spin_attack_reach: float = 68.0
@export var spin_attack_duration: float = 0.30
@export var spin_attack_cooldown: float = 0.52
@export var body_radius: float = 9.0
@export var hurt_iframes: float = 0.55

enum AttackMode { NONE, QUICK, SPIN }

var facing: Vector2 = Vector2.DOWN
var health: int = 0

var _target: MeadowEnemy
var _attack_active: bool = false
var _attack_mode: int = AttackMode.NONE
var _attack_elapsed: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _hit_targets: Array[MeadowEnemy] = []
var _attack_input_held: bool = false
var _attack_input_blocked: bool = false
var _charge_elapsed: float = 0.0
var _charge_ready: bool = false
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

    if Input.is_action_just_pressed("attack"):
        _begin_attack_input()
    _update_attack_charge(delta)
    if Input.is_action_just_released("attack"):
        _release_attack_input()

    var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var current_move_speed := move_speed
    if _attack_input_held and _charge_ready:
        current_move_speed *= spin_move_speed_multiplier
    if input_vector.length_squared() > 0.01:
        facing = input_vector.normalized()
        velocity = input_vector * current_move_speed
    else:
        velocity = Vector2.ZERO
    move_and_slide()

    if _attack_active:
        _attack_elapsed += delta
        if _attack_mode == AttackMode.SPIN:
            _try_spin_hit_targets()
        else:
            _try_hit_target()
        if _attack_elapsed >= _active_attack_duration():
            _attack_active = false
            _attack_mode = AttackMode.NONE
            _hit_targets.clear()

    queue_redraw()


func set_enemy_target(target: MeadowEnemy) -> void:
    _target = target


func get_focus_enemy() -> MeadowEnemy:
    var best: MeadowEnemy = null
    var best_score: float = INF
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
    _target = best
    return best


func is_attacking() -> bool:
    return _attack_active


func is_charging_spin() -> bool:
    return _attack_input_held and _charge_ready


func get_charge_progress() -> float:
    if not _attack_input_held:
        return 0.0
    if spin_charge_threshold <= 0.0:
        return 1.0
    return clampf(_charge_elapsed / spin_charge_threshold, 0.0, 1.0)


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
        _attack_input_held = false
        _charge_elapsed = 0.0
        _charge_ready = false
        _attack_active = false
        _attack_mode = AttackMode.NONE
        velocity = Vector2.ZERO
        defeated.emit()

    queue_redraw()
    return true


func get_state() -> Dictionary:
    return {
        "position": global_position,
        "facing": facing,
        "attacking": _attack_active,
        "attack_mode": _attack_mode_name(),
        "charging_spin": is_charging_spin(),
        "charge_ready": _charge_ready,
        "charge_progress": get_charge_progress(),
        "attack_input_blocked": _attack_input_blocked,
        "attack_cooldown": _attack_cooldown_remaining,
        "health": health,
        "max_health": max_health,
        "alive": is_alive(),
    }


func _begin_attack_input() -> void:
    if _attack_input_blocked or _is_defeated:
        return
    if _attack_active or _attack_cooldown_remaining > 0.0:
        _attack_input_blocked = true
        return

    _attack_input_held = true
    _charge_elapsed = 0.0
    _charge_ready = false
    queue_redraw()


func _update_attack_charge(delta: float) -> void:
    if not _attack_input_held:
        return

    _charge_elapsed += delta
    if not _charge_ready and _charge_elapsed >= spin_charge_threshold:
        _charge_ready = true
        spin_charge_started.emit()
    queue_redraw()


func _release_attack_input() -> void:
    if _attack_input_blocked:
        _attack_input_blocked = false
        queue_redraw()
        return
    if not _attack_input_held:
        return

    var release_as_spin := _charge_ready
    _attack_input_held = false
    _charge_elapsed = 0.0
    _charge_ready = false

    if _is_defeated or _attack_active or _attack_cooldown_remaining > 0.0:
        queue_redraw()
        return

    if release_as_spin:
        _begin_spin_attack()
    else:
        _begin_quick_attack()


func _begin_quick_attack() -> void:
    if _is_defeated or _attack_active or _attack_cooldown_remaining > 0.0:
        return

    _attack_active = true
    _attack_mode = AttackMode.QUICK
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = attack_cooldown
    _hit_targets.clear()
    attack_started.emit()
    _try_hit_target()
    queue_redraw()


func _begin_spin_attack() -> void:
    if _is_defeated or _attack_active or _attack_cooldown_remaining > 0.0:
        return

    _attack_active = true
    _attack_mode = AttackMode.SPIN
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = spin_attack_cooldown
    _hit_targets.clear()
    spin_attack_started.emit()
    _try_spin_hit_targets()
    queue_redraw()


func _active_attack_duration() -> float:
    if _attack_mode == AttackMode.SPIN:
        return spin_attack_duration
    return attack_duration


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
            _target = target
            attack_hit.emit(target, attack_damage)


func _try_spin_hit_targets() -> void:
    for candidate in get_tree().get_nodes_in_group("meadow_enemy"):
        var target := candidate as MeadowEnemy
        if target == null or _hit_targets.has(target) or not target.is_alive():
            continue

        var offset := target.global_position - global_position
        var distance := offset.length()
        if distance > spin_attack_reach + target.body_radius:
            continue

        var knockback_direction := offset.normalized()
        if knockback_direction == Vector2.ZERO:
            knockback_direction = facing
        if target.take_damage(spin_attack_damage, knockback_direction):
            _hit_targets.append(target)
            _target = target
            attack_hit.emit(target, spin_attack_damage)


func _attack_mode_name() -> String:
    match _attack_mode:
        AttackMode.QUICK:
            return "quick"
        AttackMode.SPIN:
            return "spin"
        _:
            return "none"


func _draw() -> void:
    draw_rect(Rect2(-12.0, 10.0, 24.0, 7.0), Color(0.08, 0.12, 0.16, 0.28))
    var tunic := Color("#fff1c7") if _hurt_timer > 0.0 else Color("#4c6fff")
    if _is_defeated:
        tunic = Color("#56616b")
    elif is_charging_spin():
        tunic = Color("#f2c14e")
    draw_rect(Rect2(-10.0, -10.0, 20.0, 20.0), tunic)
    draw_rect(Rect2(-7.0, -8.0, 14.0, 7.0), Color("#f0c27b"))
    draw_rect(Rect2(-5.0, -5.0, 3.0, 3.0), Color("#28324a"))
    draw_rect(Rect2(2.0, -5.0, 3.0, 3.0), Color("#28324a"))
    draw_line(Vector2.ZERO, facing * 13.0, Color("#d8e7ff"), 3.0)

    if _attack_input_held:
        var charge_progress := get_charge_progress()
        var charge_radius := 17.0 + charge_progress * 8.0
        var charge_color := Color("#f2c14e") if _charge_ready else Color(1.0, 0.95, 0.65, 0.7)
        if charge_progress > 0.0:
            draw_arc(
                Vector2.ZERO,
                charge_radius,
                -PI * 0.5,
                -PI * 0.5 + TAU * charge_progress,
                24,
                charge_color,
                3.0,
                true
            )
        if _charge_ready:
            draw_circle(Vector2.ZERO, 14.0, Color(0.95, 0.75, 0.22, 0.12))
            draw_arc(Vector2.ZERO, charge_radius, -PI * 0.5, PI * 1.5, 36, charge_color, 3.0, true)

    if _attack_active and _attack_mode == AttackMode.SPIN:
        var spin_progress := clampf(
            _attack_elapsed / maxf(spin_attack_duration, 0.001),
            0.0,
            1.0
        )
        var spin_alpha := 1.0 - spin_progress
        draw_circle(
            Vector2.ZERO,
            spin_attack_reach * 0.78,
            Color(0.95, 0.65, 0.18, 0.08 * spin_alpha)
        )
        draw_arc(
            Vector2.ZERO,
            spin_attack_reach * 0.82,
            -PI * 0.5,
            PI * 1.5,
            48,
            Color(0.95, 0.88, 0.55, 0.9 * spin_alpha),
            7.0,
            true
        )
        draw_arc(
            Vector2.ZERO,
            spin_attack_reach * 0.58,
            -PI * 0.5,
            PI * 1.5,
            36,
            Color(1.0, 0.97, 0.82, 0.65 * spin_alpha),
            3.0,
            true
        )
    elif _attack_active:
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
