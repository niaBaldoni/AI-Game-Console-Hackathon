extends Node2D
class_name OpenMeadow

const WORLD_SIZE := Vector2(2400.0, 1350.0)
const OBSTACLES := [
    {"position": Vector2(890.0, 350.0), "size": Vector2(170.0, 42.0)},
    {"position": Vector2(1210.0, 780.0), "size": Vector2(210.0, 42.0)},
    {"position": Vector2(1790.0, 440.0), "size": Vector2(150.0, 42.0)},
]

@onready var player: MeadowPlayer = $Player
@onready var enemy: MeadowEnemy = $Enemy
@onready var hud: MeadowHud = $HUD
@onready var obstacles: Node2D = $Obstacles


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    _build_world_collisions()

    player.set_enemy_target(enemy)
    player.attack_started.connect(_on_player_attack_started)
    player.attack_hit.connect(_on_player_attack_hit)
    enemy.health_changed.connect(_on_enemy_health_changed)
    enemy.defeated.connect(_on_enemy_defeated)

    hud.set_enemy_health(enemy.health, enemy.max_health)
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#6ea85a"))

    for x in range(0, int(WORLD_SIZE.x), 64):
        for y in range(0, int(WORLD_SIZE.y), 64):
            var tile_index := floori(float(x) / 64.0) + floori(float(y) / 64.0)
            if tile_index % 3 == 0:
                draw_rect(Rect2(x + 8, y + 8, 28, 18), Color("#74b761"))

    draw_rect(Rect2(0.0, 565.0, WORLD_SIZE.x, 76.0), Color("#d7a36d"))
    draw_rect(Rect2(0.0, 594.0, WORLD_SIZE.x, 18.0), Color("#e5b77a"))
    draw_rect(Rect2(1080.0, 0.0, 74.0, WORLD_SIZE.y), Color("#d7a36d"))
    draw_rect(Rect2(1108.0, 0.0, 18.0, WORLD_SIZE.y), Color("#e5b77a"))

    for obstacle: Dictionary in OBSTACLES:
        var obstacle_position: Vector2 = obstacle["position"]
        var obstacle_size: Vector2 = obstacle["size"]
        draw_rect(
            Rect2(obstacle_position - obstacle_size * 0.5, obstacle_size),
            Color("#416f4a")
        )
        draw_rect(
            Rect2(obstacle_position - obstacle_size * 0.5 + Vector2(5.0, 5.0), obstacle_size - Vector2(10.0, 10.0)),
            Color("#5b8f52")
        )

    var trees := [
        Vector2(220.0, 210.0),
        Vector2(380.0, 1040.0),
        Vector2(1540.0, 180.0),
        Vector2(2070.0, 980.0),
        Vector2(2180.0, 260.0),
    ]
    for tree_position: Vector2 in trees:
        draw_circle(tree_position + Vector2(0.0, 12.0), 24.0, Color("#416f4a"))
        draw_circle(tree_position, 19.0, Color("#31724c"))
        draw_rect(Rect2(tree_position + Vector2(-4.0, 14.0), Vector2(8.0, 17.0)), Color("#8a5945"))

    draw_rect(Rect2(0.0, 0.0, WORLD_SIZE.x, 10.0), Color("#263238"))
    draw_rect(Rect2(0.0, WORLD_SIZE.y - 10.0, WORLD_SIZE.x, 10.0), Color("#263238"))
    draw_rect(Rect2(0.0, 0.0, 10.0, WORLD_SIZE.y), Color("#263238"))
    draw_rect(Rect2(WORLD_SIZE.x - 10.0, 0.0, 10.0, WORLD_SIZE.y), Color("#263238"))


func _build_world_collisions() -> void:
    _add_boundary(Vector2(WORLD_SIZE.x * 0.5, -12.0), Vector2(WORLD_SIZE.x, 24.0), "NorthBoundary")
    _add_boundary(Vector2(WORLD_SIZE.x * 0.5, WORLD_SIZE.y + 12.0), Vector2(WORLD_SIZE.x, 24.0), "SouthBoundary")
    _add_boundary(Vector2(-12.0, WORLD_SIZE.y * 0.5), Vector2(24.0, WORLD_SIZE.y), "WestBoundary")
    _add_boundary(Vector2(WORLD_SIZE.x + 12.0, WORLD_SIZE.y * 0.5), Vector2(24.0, WORLD_SIZE.y), "EastBoundary")

    for index in OBSTACLES.size():
        var obstacle: Dictionary = OBSTACLES[index]
        _add_boundary(obstacle["position"], obstacle["size"], "MeadowObstacle%d" % index)


func _add_boundary(center: Vector2, size: Vector2, node_name: String) -> void:
    var body := StaticBody2D.new()
    body.name = node_name
    body.position = center
    body.collision_layer = 1
    body.collision_mask = 1

    var collision := CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = size
    collision.shape = rectangle
    body.add_child(collision)
    obstacles.add_child(body)


func _on_player_attack_started() -> void:
    hud.show_message("SWORD SWING")


func _on_player_attack_hit(_target: MeadowEnemy, _damage: int) -> void:
    hud.show_message("HIT!")


func _on_enemy_health_changed(current_health: int, maximum_health: int) -> void:
    hud.set_enemy_health(current_health, maximum_health)


func _on_enemy_defeated() -> void:
    hud.show_message("ENEMY DEFEATED")
