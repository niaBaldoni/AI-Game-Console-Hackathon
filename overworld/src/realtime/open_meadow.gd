extends Node2D
class_name OpenMeadow

const WORLD_SIZE := Vector2(2400.0, 1350.0)
const MAX_ACTIVE_ENEMIES := 8
const SPAWN_MARGIN := 24.0
const OBSTACLES := [
    {"position": Vector2(890.0, 350.0), "size": Vector2(170.0, 42.0)},
    {"position": Vector2(1210.0, 780.0), "size": Vector2(210.0, 42.0)},
    {"position": Vector2(1790.0, 440.0), "size": Vector2(150.0, 42.0)},
]

@onready var player: MeadowPlayer = $Player
@onready var enemies: Node2D = $Enemies
@onready var hud: MeadowHud = $HUD
@onready var obstacles: Node2D = $Obstacles

var _next_enemy_runtime_id: int = 1
var _summary_refresh_timer: float = 0.0


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    _ensure_host_mcp_files()
    _build_world_collisions()

    for child in enemies.get_children():
        var enemy := child as MeadowEnemy
        if enemy != null:
            _register_enemy(enemy)

    player.attack_started.connect(_on_player_attack_started)
    player.attack_hit.connect(_on_player_attack_hit)
    AgentBridge.enemy_spawn_requested.connect(_on_enemy_spawn_requested)

    _publish_agent_summary()
    queue_redraw()


func _process(delta: float) -> void:
    _summary_refresh_timer -= delta
    if _summary_refresh_timer <= 0.0:
        _summary_refresh_timer = 0.1
        _publish_agent_summary()


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
            Rect2(
                obstacle_position - obstacle_size * 0.5 + Vector2(5.0, 5.0),
                obstacle_size - Vector2(10.0, 10.0)
            ),
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
    _add_boundary(
        Vector2(WORLD_SIZE.x * 0.5, -12.0),
        Vector2(WORLD_SIZE.x, 24.0),
        "NorthBoundary"
    )
    _add_boundary(
        Vector2(WORLD_SIZE.x * 0.5, WORLD_SIZE.y + 12.0),
        Vector2(WORLD_SIZE.x, 24.0),
        "SouthBoundary"
    )
    _add_boundary(
        Vector2(-12.0, WORLD_SIZE.y * 0.5),
        Vector2(24.0, WORLD_SIZE.y),
        "WestBoundary"
    )
    _add_boundary(
        Vector2(WORLD_SIZE.x + 12.0, WORLD_SIZE.y * 0.5),
        Vector2(24.0, WORLD_SIZE.y),
        "EastBoundary"
    )

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


func _register_enemy(enemy: MeadowEnemy) -> void:
    if enemy.runtime_id <= 0:
        enemy.runtime_id = _next_enemy_runtime_id
        _next_enemy_runtime_id += 1
    enemy.health_changed.connect(_on_enemy_health_changed.bind(enemy))
    enemy.defeated.connect(_on_enemy_defeated.bind(enemy))


func _on_enemy_spawn_requested(
    request_id: int,
    spawn_position: Vector2,
    health: int
) -> void:
    if _alive_enemy_count() >= MAX_ACTIVE_ENEMIES:
        AgentBridge.resolve_spawn_request(request_id, {
            "accepted": false,
            "error_code": "enemy_limit_reached",
            "error_message": "The meadow enemy roster is full",
        })
        hud.show_message("ENEMY ROSTER FULL")
        return

    if spawn_position.x < SPAWN_MARGIN or spawn_position.x > WORLD_SIZE.x - SPAWN_MARGIN:
        AgentBridge.resolve_spawn_request(request_id, {
            "accepted": false,
            "error_code": "spawn_out_of_bounds",
            "error_message": "The spawn position is outside the meadow",
        })
        hud.show_message("SPAWN OUT OF BOUNDS")
        return
    if spawn_position.y < SPAWN_MARGIN or spawn_position.y > WORLD_SIZE.y - SPAWN_MARGIN:
        AgentBridge.resolve_spawn_request(request_id, {
            "accepted": false,
            "error_code": "spawn_out_of_bounds",
            "error_message": "The spawn position is outside the meadow",
        })
        hud.show_message("SPAWN OUT OF BOUNDS")
        return

    var enemy := MeadowEnemy.new()
    enemy.name = "Enemy_%03d" % request_id
    enemy.runtime_id = _next_enemy_runtime_id
    _next_enemy_runtime_id += 1
    enemy.max_health = health
    enemy.position = spawn_position
    enemies.add_child(enemy)
    _register_enemy(enemy)

    AgentBridge.resolve_spawn_request(request_id, {
        "accepted": true,
        "spawned": true,
        "request_id": request_id,
        "enemy_id": enemy.runtime_id,
        "position": spawn_position,
        "health": health,
    })
    hud.show_message("ENEMY SPAWNED")
    _publish_agent_summary()


func _alive_enemy_count() -> int:
    var count := 0
    for child in enemies.get_children():
        var enemy := child as MeadowEnemy
        if enemy != null and enemy.is_alive():
            count += 1
    return count


func _publish_agent_summary() -> void:
    var enemy_states: Array[Dictionary] = []
    for child in enemies.get_children():
        var enemy := child as MeadowEnemy
        if enemy != null and enemy.is_alive():
            enemy_states.append(enemy.get_state())

    hud.set_enemy_count(enemy_states.size(), MAX_ACTIVE_ENEMIES)
    AgentBridge.publish_summary({
        "player": player.get_state(),
        "enemies": enemy_states,
    })


func _on_player_attack_started() -> void:
    hud.show_message("SWORD SWING")


func _on_player_attack_hit(target: MeadowEnemy, _damage: int) -> void:
    hud.show_message("HIT ENEMY %d" % target.runtime_id)


func _on_enemy_health_changed(
    current_health: int,
    maximum_health: int,
    _enemy: MeadowEnemy
) -> void:
    hud.set_enemy_health(current_health, maximum_health)
    _publish_agent_summary()


func _on_enemy_defeated(enemy: MeadowEnemy) -> void:
    hud.show_message("ENEMY %d DEFEATED" % enemy.runtime_id)
    _publish_agent_summary()


func _ensure_host_mcp_files() -> void:
    if not OS.has_feature("release"):
        return

    var app_root := ProjectSettings.globalize_path("res://")
    var runtime_directory := app_root.path_join("runtime-mcp")
    var cursor_directory := app_root.path_join(".cursor")
    var rules_directory := cursor_directory.path_join("rules")
    if DirAccess.make_dir_recursive_absolute(runtime_directory) != OK:
        push_warning("Open Meadow could not create the runtime MCP directory")
        return
    if DirAccess.make_dir_recursive_absolute(cursor_directory) != OK:
        push_warning("Open Meadow could not create the Cursor config directory")
        return
    if DirAccess.make_dir_recursive_absolute(rules_directory) != OK:
        push_warning("Open Meadow could not create the Cursor rules directory")
        return

    var server_source := FileAccess.get_file_as_string("res://runtime-mcp/server.py")
    var client_source := FileAccess.get_file_as_string("res://runtime-mcp/game_client.py")
    if server_source.is_empty() or client_source.is_empty():
        push_warning("Open Meadow release is missing its embedded runtime MCP files")
        return

    _write_host_file(runtime_directory.path_join("server.py"), server_source)
    _write_host_file(runtime_directory.path_join("game_client.py"), client_source)

    var rule_source := FileAccess.get_file_as_string("res://runtime-mcp/summer-runtime.mdc")
    if not rule_source.is_empty():
        _write_host_file(rules_directory.path_join("summer-runtime.mdc"), rule_source)

    var config := {
        "mcpServers": {
            "summer-runtime": {
                "command": "python3",
                "args": ["$" + "{workspaceFolder}/runtime-mcp/server.py"],
                "env": {
                    "SUMMER_GAME_MCP_HOST": "127.0.0.1",
                    "SUMMER_GAME_MCP_PORT": "8765",
                    "SUMMER_GAME_MCP_TIMEOUT": "2.0",
                    "SUMMER_GAME_MCP_DIR": "/home/arduino/ArduinoApps/open-meadow/game/.runtime-mcp",
                },
            },
        },
    }
    _write_host_file(cursor_directory.path_join("mcp.json"), JSON.stringify(config, "  "))


func _write_host_file(path: String, content: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_warning("Open Meadow could not write %s" % path)
        return
    file.store_string(content)
    file.close()
