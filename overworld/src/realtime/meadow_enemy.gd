extends CharacterBody2D
class_name MeadowEnemy

signal health_changed(current_health: int, maximum_health: int)
signal defeated
signal hit_landed(damage: int)
signal attack_started
signal attack_hit(target: MeadowPlayer, damage: int)

enum Kind { MELEE, RANGED }

const KIND_NAMES := {
    Kind.MELEE: "BRUTE",
    Kind.RANGED: "MAGE",
}

const FIREBALL_SCENE := preload("res://src/realtime/meadow_fireball.gd")

@export var kind: Kind = Kind.MELEE
@export var max_health: int = 6
@export var move_speed: float = 80.0
@export var detect_range: float = 170.0
@export var attack_range: float = 50.0
@export var attack_damage: int = 1
@export var attack_reach: float = 50.0
@export var attack_width: float = 20.0
@export var attack_duration: float = 0.16
@export var attack_cooldown: float = 0.9
@export var knockback_speed: float = 110.0
@export var knockback_duration: float = 0.16
@export var body_radius: float = 18.0
@export var keep_distance: float = 210.0
@export var fireball_speed: float = 170.0
@export var charge_chance: float = 0.38
@export var charge_duration: float = 0.9
@export var charged_fireball_damage: int = 2
@export var charged_fireball_speed: float = 145.0
@export var charged_fireball_radius: float = 16.0

var health: int = 0
var runtime_id: int = 0
var facing: Vector2 = Vector2.DOWN

var _player: MeadowPlayer
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0
var _hurt_timer: float = 0.0
var _is_defeated: bool = false
var _is_aggro: bool = false
var _body_color: Color = Color("#d95763")
var _attack_active: bool = false
var _attack_elapsed: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _has_hit: bool = false
var _charging: bool = false
var _charge_elapsed: float = 0.0


func _ready() -> void:
    add_to_group("meadow_enemy")
    _ensure_collision_shape()
    apply_kind(kind)
    queue_redraw()


func set_player(player: MeadowPlayer) -> void:
    _player = player


func apply_kind(enemy_kind: Kind) -> void:
    kind = enemy_kind
    match kind:
        Kind.MELEE:
            max_health = 3
            body_radius = 22.0
            move_speed = 46.0
            detect_range = 170.0
            attack_range = 48.0
            attack_reach = 50.0
            attack_duration = 0.16
            attack_cooldown = 0.92
            attack_damage = 1
            knockback_speed = 100.0
            _body_color = Color("#d95763")
        Kind.RANGED:
            max_health = 2
            body_radius = 15.0
            move_speed = 80.0
            detect_range = 340.0
            attack_range = 280.0
            keep_distance = 200.0
            attack_duration = 0.12
            attack_cooldown = 1.35
            attack_damage = 1
            fireball_speed = 170.0
            charge_chance = 0.38
            charge_duration = 0.9
            charged_fireball_damage = 2
            charged_fireball_speed = 145.0
            charged_fireball_radius = 16.0
            knockback_speed = 150.0
            _body_color = Color("#7a4ad1")

    health = max_health
    _is_defeated = false
    _is_aggro = false
    _attack_active = false
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = 0.0
    _has_hit = false
    _charging = false
    _charge_elapsed = 0.0
    _sync_collision()
    health_changed.emit(health, max_health)
    queue_redraw()


func _ensure_collision_shape() -> void:
    var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision == null:
        collision = CollisionShape2D.new()
        collision.name = "CollisionShape2D"
        add_child(collision)
    if collision.shape == null:
        collision.shape = RectangleShape2D.new()


func _sync_collision() -> void:
    var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision == null:
        return
    var rectangle := collision.shape as RectangleShape2D
    if rectangle == null:
        rectangle = RectangleShape2D.new()
        collision.shape = rectangle
    rectangle.size = Vector2(body_radius * 1.7, body_radius * 1.7)


func _physics_process(delta: float) -> void:
    if _is_defeated:
        velocity = Vector2.ZERO
        return

    _attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
    _hurt_timer = maxf(_hurt_timer - delta, 0.0)

    if _knockback_timer > 0.0:
        _cancel_charge()
        velocity = _knockback_velocity
        move_and_slide()
        _knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 950.0 * delta)
        _knockback_timer -= delta
        queue_redraw()
        return

    if _charging:
        _update_charge(delta)
        move_and_slide()
        queue_redraw()
        return

    _update_combat()
    move_and_slide()

    if _attack_active:
        _attack_elapsed += delta
        if kind == Kind.MELEE:
            _try_melee_hit()
        if _attack_elapsed >= attack_duration:
            _attack_active = false

    queue_redraw()


func _update_combat() -> void:
    velocity = Vector2.ZERO
    if _player == null or not is_instance_valid(_player) or not _player.is_alive():
        _is_aggro = false
        return

    var offset := _player.global_position - global_position
    var distance := offset.length()
    if distance <= detect_range:
        _is_aggro = true
    elif distance > detect_range * 1.35:
        _is_aggro = false

    if not _is_aggro:
        return

    if offset != Vector2.ZERO:
        facing = offset.normalized()

    match kind:
        Kind.MELEE:
            if distance <= attack_range + _player.body_radius:
                _begin_attack()
            else:
                velocity = facing * move_speed
        Kind.RANGED:
            if distance < keep_distance * 0.72:
                velocity = -facing * move_speed
            elif distance > attack_range:
                velocity = facing * move_speed
            else:
                _begin_attack()


func _begin_attack() -> void:
    if _charging or _attack_active or _attack_cooldown_remaining > 0.0:
        return

    if kind == Kind.RANGED and randf() < charge_chance:
        _start_charge()
        return

    _attack_active = true
    _attack_elapsed = 0.0
    _attack_cooldown_remaining = attack_cooldown
    _has_hit = false
    attack_started.emit()

    if kind == Kind.MELEE:
        _try_melee_hit()
    else:
        _spawn_fireball(false)


func _start_charge() -> void:
    _charging = true
    _charge_elapsed = 0.0
    _attack_cooldown_remaining = attack_cooldown
    velocity = Vector2.ZERO
    attack_started.emit()


func _update_charge(delta: float) -> void:
    velocity = Vector2.ZERO
    if _player != null and is_instance_valid(_player) and _player.is_alive():
        var offset := _player.global_position - global_position
        if offset != Vector2.ZERO:
            facing = offset.normalized()
    _charge_elapsed += delta
    if _charge_elapsed >= charge_duration:
        _charging = false
        _spawn_fireball(true)


func _cancel_charge() -> void:
    _charging = false
    _charge_elapsed = 0.0


func _try_melee_hit() -> void:
    if _has_hit or _player == null or not _player.is_alive():
        return

    var offset := _player.global_position - global_position
    var distance := offset.length()
    if distance > attack_reach + _player.body_radius:
        return

    var target_direction := offset.normalized()
    if target_direction == Vector2.ZERO or facing.dot(target_direction) < 0.2:
        return

    if _player.take_damage(attack_damage, facing):
        _has_hit = true
        attack_hit.emit(_player, attack_damage)


func _spawn_fireball(charged: bool = false) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var fireball: MeadowFireball = FIREBALL_SCENE.new()
    var origin := global_position + facing * (body_radius + 12.0)
    if charged:
        fireball.setup(
            origin,
            facing,
            charged_fireball_damage,
            charged_fireball_speed,
            charged_fireball_radius
        )
    else:
        fireball.setup(origin, facing, attack_damage, fireball_speed, 7.0)
    parent.add_child(fireball)


func is_alive() -> bool:
    return not _is_defeated


func take_damage(amount: int, direction: Vector2) -> bool:
    if _is_defeated:
        return false

    var applied_damage := maxi(amount, 1)
    health = maxi(health - applied_damage, 0)
    _hurt_timer = 0.14
    _is_aggro = true
    _cancel_charge()
    _attack_active = false

    var knockback_direction := direction.normalized()
    if knockback_direction == Vector2.ZERO:
        knockback_direction = Vector2.DOWN
    _knockback_velocity = knockback_direction * knockback_speed
    _knockback_timer = knockback_duration

    hit_landed.emit(applied_damage)
    health_changed.emit(health, max_health)

    if health == 0:
        _is_defeated = true
        _attack_active = false
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
        "kind": kind,
        "kind_name": get_kind_name(),
        "aggro": _is_aggro,
        "charging": _charging,
    }


func get_kind_name() -> String:
    return str(KIND_NAMES.get(kind, "MELEE"))


func get_difficulty_name() -> String:
    return get_kind_name()


func get_radar_color() -> Color:
    if kind == Kind.RANGED:
        return Color("#c084fc")
    return Color("#ff5b5b")


func get_radar_blip_radius() -> float:
    if kind == Kind.RANGED:
        return 4.6
    return 6.4


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
        draw_line(Vector2.ZERO, facing * (body_radius * 0.85), Color("#fff1c7"), 3.0)
        var eye_w := maxf(body_radius * 0.28, 4.0)
        var eye_h := maxf(body_radius * 0.18, 3.0)
        draw_rect(Rect2(-body_radius * 0.55, -body_radius * 0.28, eye_w, eye_h), Color("#fff1c7"))
        draw_rect(Rect2(body_radius * 0.22, -body_radius * 0.28, eye_w, eye_h), Color("#fff1c7"))
        if kind == Kind.RANGED:
            draw_rect(Rect2(-body_radius * 0.35, -body_radius * 0.95, body_radius * 0.7, body_radius * 0.35), Color("#5b2ea6"))
            draw_circle(Vector2(0.0, -body_radius * 1.05), 4.0, Color("#ff7a2e"))
            if _charging:
                var charge_ratio := clampf(_charge_elapsed / maxf(charge_duration, 0.01), 0.0, 1.0)
                var charge_radius := 6.0 + charged_fireball_radius * charge_ratio
                draw_circle(facing * (body_radius + 10.0), charge_radius, Color(1.0, 0.55, 0.2, 0.35 + 0.45 * charge_ratio))
                draw_circle(facing * (body_radius + 10.0), charge_radius * 0.45, Color("#fff1c7"))
        else:
            draw_rect(Rect2(-body_radius * 0.45, body_radius * 0.18, body_radius * 0.9, body_radius * 0.22), Color("#8f3548"))

        if _attack_active and kind == Kind.MELEE:
            var side := Vector2(-facing.y, facing.x)
            var origin := facing * 9.0
            var tip := facing * attack_reach
            var points := PackedVector2Array([
                origin - side * (attack_width * 0.5),
                tip,
                origin + side * (attack_width * 0.5),
            ])
            draw_colored_polygon(points, Color(0.95, 0.55, 0.45, 0.9))

    var health_ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
    var bar_width := body_radius * 2.4
    draw_rect(Rect2(-bar_width * 0.5, -body_radius - 15.0, bar_width, 5.0), Color("#263238"))
    draw_rect(Rect2(-bar_width * 0.5, -body_radius - 15.0, bar_width * health_ratio, 5.0), Color("#f2c14e"))
