extends Area2D
class_name MeadowFireball

@export var travel_speed: float = 240.0
@export var lifetime: float = 1.8
@export var damage: int = 1

var _direction: Vector2 = Vector2.RIGHT
var _time_alive: float = 0.0
var _spent: bool = false
var _visual_radius: float = 8.0
var _hit_radius: float = 3.5


func setup(
	origin: Vector2,
	direction: Vector2,
	projectile_damage: int,
	speed: float = 240.0,
	visual_radius: float = 8.0,
	hit_radius: float = 3.5
) -> void:
	global_position = origin
	_direction = direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	damage = maxi(projectile_damage, 1)
	travel_speed = speed
	_visual_radius = visual_radius
	_hit_radius = hit_radius
	lifetime = 1.8 if visual_radius <= 10.0 else 2.3
	rotation = _direction.angle()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _hit_radius
	collision.shape = circle
	add_child(collision)

	body_entered.connect(_on_body_entered)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	global_position += _direction * travel_speed * delta
	_time_alive += delta
	if _time_alive >= lifetime:
		_spend()
		return
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if _spent:
		return
	var player := body as MeadowPlayer
	if player != null:
		player.take_damage(damage, _direction)
		_spend()
		return
	if body is MeadowEnemy:
		return
	_spend()


func _spend() -> void:
	_spent = true
	queue_free()


func _draw() -> void:
	draw_circle(Vector2(-4.0, 3.0), _visual_radius + 1.0, Color(0.08, 0.12, 0.16, 0.22))
	draw_circle(Vector2.ZERO, _visual_radius + 1.0, Color("#ff7a2e"))
	draw_circle(Vector2(-2.0, -1.0), _visual_radius * 0.55, Color("#ffd35c"))
	draw_circle(Vector2(_visual_radius * 0.35, 1.0), _visual_radius * 0.28, Color("#fff1c7"))
