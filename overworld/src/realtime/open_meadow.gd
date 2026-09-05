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
const PACK := [
    {"position": Vector2(720.0, 270.0), "kind": MeadowEnemy.Kind.MELEE},
    {"position": Vector2(980.0, 430.0), "kind": MeadowEnemy.Kind.RANGED},
    {"position": Vector2(390.0, 920.0), "kind": MeadowEnemy.Kind.MELEE},
    {"position": Vector2(1480.0, 640.0), "kind": MeadowEnemy.Kind.RANGED},
    {"position": Vector2(760.0, 1120.0), "kind": MeadowEnemy.Kind.RANGED},
    {"position": Vector2(1980.0, 300.0), "kind": MeadowEnemy.Kind.MELEE},
    {"position": Vector2(2080.0, 1120.0), "kind": MeadowEnemy.Kind.RANGED},
]

@onready var player: MeadowPlayer = $Player
@onready var enemies: Node2D = $Enemies
@onready var hud: MeadowHud = $HUD
@onready var obstacles: Node2D = $Obstacles

var pause_menu: MeadowPauseMenu
var _next_enemy_runtime_id: int = 1
var _summary_refresh_timer: float = 0.0


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    _ensure_host_mcp_files()
    _build_world_collisions()
    _spawn_pack()
    _spawn_pickups()

    for child in enemies.get_children():
        var enemy := child as MeadowEnemy
        if enemy != null:
            _register_enemy(enemy)

    player.attack_started.connect(_on_player_attack_started)
    player.spin_charge_started.connect(_on_player_spin_charge_started)
    player.spin_attack_started.connect(_on_player_spin_attack_started)
    player.attack_hit.connect(_on_player_attack_hit)
    player.damaged.connect(_on_player_damaged)
    player.defeated.connect(_on_player_defeated)
    player.health_changed.connect(_on_player_health_changed)
    hud.bind_player(player, WORLD_SIZE)
    hud.set_player_health(player.health, player.max_health)
    AgentBridge.enemy_spawn_requested.connect(_on_enemy_spawn_requested)
    _setup_pause_menu()

    _publish_agent_summary()
    queue_redraw()


func _process(delta: float) -> void:
    _summary_refresh_timer -= delta
    if _summary_refresh_timer <= 0.0:
        _summary_refresh_timer = 0.1
        _publish_agent_summary()
    hud.set_tracked_enemy(player.get_focus_enemy())


func _draw() -> void:
    for region: Dictionary in MeadowWorld.regions():
        var region_rect: Rect2 = region["rect"]
        var fill: Color = region["fill"]
        var dot: Color = region["dot"]
        draw_rect(region_rect, fill)
        var start_x := int(region_rect.position.x)
        var start_y := int(region_rect.position.y)
        var end_x := int(region_rect.end.x)
        var end_y := int(region_rect.end.y)
        for x in range(start_x, end_x, 64):
            for y in range(start_y, end_y, 64):
                var tile_index := floori(float(x) / 64.0) + floori(float(y) / 64.0)
                if tile_index % 3 == 0:
                    draw_rect(Rect2(x + 8, y + 8, 28, 18), dot)

        var label_position := region_rect.position + Vector2(36.0, 36.0)
        var font := ThemeDB.fallback_font
        if font != null:
            draw_string(font, label_position, str(region["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, region["label"])

    draw_rect(Rect2(0.0, MeadowWorld.ROAD_Y, WORLD_SIZE.x, MeadowWorld.ROAD_WIDTH), Color("#d7a36d"))
    draw_rect(Rect2(0.0, MeadowWorld.ROAD_Y + 29.0, WORLD_SIZE.x, 18.0), Color("#e5b77a"))
    draw_rect(Rect2(MeadowWorld.ROAD_X, 0.0, MeadowWorld.ROAD_WIDTH, WORLD_SIZE.y), Color("#d7a36d"))
    draw_rect(Rect2(MeadowWorld.ROAD_X + 28.0, 0.0, 18.0, WORLD_SIZE.y), Color("#e5b77a"))

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
        var canopy := Color("#416f4a")
        var leaf := Color("#31724c")
        if tree_position.y < MeadowWorld.ROAD_Y and tree_position.x < MeadowWorld.ROAD_X:
            canopy = Color("#d9f4ff")
            leaf = Color("#b7e4f4")
        elif tree_position.y < MeadowWorld.ROAD_Y:
            canopy = Color("#c45c32")
            leaf = Color("#e0893a")
        elif tree_position.x < MeadowWorld.ROAD_X:
            canopy = Color("#5b3d86")
            leaf = Color("#8d63c4")
        draw_circle(tree_position + Vector2(0.0, 12.0), 24.0, canopy)
        draw_circle(tree_position, 19.0, leaf)
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


func _spawn_pack() -> void:
    if PACK.is_empty():
        return

    var first_spec: Dictionary = PACK[0]
    var first_enemy := enemies.get_node_or_null("Enemy") as MeadowEnemy
    if first_enemy == null:
        first_enemy = MeadowEnemy.new()
        first_enemy.name = "Enemy"
        enemies.add_child(first_enemy)
    first_enemy.position = first_spec["position"]
    first_enemy.apply_kind(first_spec["kind"])
    _wire_enemy(first_enemy)

    for index in range(1, PACK.size()):
        var spec: Dictionary = PACK[index]
        var spawned := first_enemy.duplicate() as MeadowEnemy
        if spawned == null:
            continue
        spawned.name = "Enemy%d" % index
        spawned.runtime_id = 0
        spawned.position = spec["position"]
        enemies.add_child(spawned)
        spawned.apply_kind(spec["kind"])
        _wire_enemy(spawned)


func _spawn_pickups() -> void:
    var specs := [
        {"position": Vector2(260.0, 180.0), "kind": MeadowPickup.Kind.HEART},
        {"position": Vector2(1680.0, 220.0), "kind": MeadowPickup.Kind.POWER},
        {"position": Vector2(240.0, 980.0), "kind": MeadowPickup.Kind.SHIELD},
        {"position": Vector2(1960.0, 980.0), "kind": MeadowPickup.Kind.HEART},
        {"position": Vector2(1180.0, 430.0), "kind": MeadowPickup.Kind.HEART},
        {"position": Vector2(900.0, 1180.0), "kind": MeadowPickup.Kind.POWER},
        {"position": Vector2(2100.0, 160.0), "kind": MeadowPickup.Kind.SHIELD},
    ]
    var folder := get_node_or_null("Pickups") as Node2D
    if folder == null:
        folder = Node2D.new()
        folder.name = "Pickups"
        add_child(folder)
    for index in specs.size():
        var spec: Dictionary = specs[index]
        var pickup := MeadowPickup.new()
        pickup.name = "Pickup%d" % index
        pickup.position = spec["position"]
        pickup.kind = spec["kind"]
        pickup.collected.connect(_on_pickup_collected)
        folder.add_child(pickup)


func _on_pickup_collected(kind: MeadowPickup.Kind) -> void:
    match kind:
        MeadowPickup.Kind.HEART:
            hud.show_message("HEART!")
            hud.set_player_health(player.health, player.max_health)
        MeadowPickup.Kind.POWER:
            hud.show_message("POWER UP!")
        MeadowPickup.Kind.SHIELD:
            hud.show_message("SHIELD ON!")


func _wire_enemy(enemy: MeadowEnemy) -> void:
    enemy.set_player(player)
    if not enemy.attack_hit.is_connected(_on_enemy_attack_hit):
        enemy.attack_hit.connect(_on_enemy_attack_hit)


func _register_enemy(enemy: MeadowEnemy) -> void:
    if enemy.runtime_id <= 0:
        enemy.runtime_id = _next_enemy_runtime_id
        _next_enemy_runtime_id += 1
    _wire_enemy(enemy)
    if not enemy.health_changed.is_connected(_on_enemy_health_changed.bind(enemy)):
        enemy.health_changed.connect(_on_enemy_health_changed.bind(enemy))
    if not enemy.defeated.is_connected(_on_enemy_defeated.bind(enemy)):
        enemy.defeated.connect(_on_enemy_defeated.bind(enemy))


func _on_enemy_spawn_requested(
    request_id: int,
    spawn_position: Vector2,
    health: int,
    kind_name: String,
    override_health: bool
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
    enemy.position = spawn_position
    var kind := MeadowEnemy.Kind.RANGED if kind_name == "mage" else MeadowEnemy.Kind.MELEE
    enemy.kind = kind
    enemies.add_child(enemy)
    enemy.apply_kind(kind)
    if override_health:
        enemy.max_health = maxi(health, 1)
        enemy.health = enemy.max_health
        enemy.health_changed.emit(enemy.health, enemy.max_health)
    _register_enemy(enemy)

    AgentBridge.resolve_spawn_request(request_id, {
        "accepted": true,
        "spawned": true,
        "request_id": request_id,
        "enemy_id": enemy.runtime_id,
        "position": spawn_position,
        "health": enemy.health,
        "kind": enemy.get_kind_name().to_lower(),
    })
    hud.show_message("%s SPAWNED" % enemy.get_kind_name())
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


func _on_player_spin_charge_started() -> void:
    hud.show_message("CHARGE SPIN")


func _on_player_spin_attack_started() -> void:
    hud.show_message("SPIN ATTACK")


func _on_player_attack_hit(target: MeadowEnemy, _damage: int) -> void:
    hud.show_message("HIT ENEMY %d" % target.runtime_id)


func _on_enemy_attack_hit(_target: MeadowPlayer, _damage: int) -> void:
    hud.show_message("YOU WERE HIT")


func _on_player_damaged(_amount: int) -> void:
    hud.show_message("YOU WERE HIT")


func _on_player_health_changed(current_health: int, maximum_health: int) -> void:
    hud.set_player_health(current_health, maximum_health)


func _on_player_defeated() -> void:
    hud.show_message("YOU FELL")
    if pause_menu != null:
        pause_menu.open_defeated()


func _setup_pause_menu() -> void:
    pause_menu = MeadowPauseMenu.new()
    pause_menu.name = "PauseMenu"
    pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(pause_menu)
    pause_menu.play_selected.connect(_on_menu_play)
    pause_menu.back_selected.connect(_on_menu_back)
    pause_menu.restart_selected.connect(_on_menu_restart)
    pause_menu.quit_selected.connect(_on_menu_quit)
    if MeadowPauseMenu.start_in_game:
        MeadowPauseMenu.start_in_game = false
        get_tree().paused = false
    else:
        pause_menu.open_title()


func _on_menu_play() -> void:
    get_tree().paused = false


func _on_menu_back() -> void:
    MeadowPauseMenu.start_in_game = false
    _reload_meadow()


func _on_menu_restart() -> void:
    MeadowPauseMenu.start_in_game = true
    _reload_meadow()


func _on_menu_quit() -> void:
    get_tree().paused = false
    get_tree().quit()


func _reload_meadow() -> void:
    get_tree().paused = false
    get_tree().reload_current_scene()


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
                # The Uno Q Cursor CLI does not expand ${workspaceFolder} in
                # stdio command arguments. Keep this absolute path aligned
                # with the App Lab mount used by the file bridge.
                "args": ["/home/arduino/ArduinoApps/open-meadow/game/runtime-mcp/server.py"],
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
