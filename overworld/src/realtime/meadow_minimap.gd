extends Control
class_name MeadowMinimap

const RADAR_RANGE := 560.0

var player: MeadowPlayer
var world_size: Vector2 = Vector2(2400.0, 1350.0)


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var radar_size := minf(size.x, size.y)
    var center := Vector2(radar_size, radar_size) * 0.5
    var radius := radar_size * 0.5 - 8.0

    draw_circle(center, radius + 7.0, Color(0.05, 0.07, 0.09, 0.96))
    draw_circle(center, radius + 3.0, Color("#c9a227"))
    draw_circle(center, radius, Color(0.16, 0.28, 0.20, 0.94))
    draw_arc(center, radius * 0.55, 0.0, TAU, 48, Color(0.32, 0.48, 0.34, 0.35), 1.5, true)
    draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), Color(0.32, 0.48, 0.34, 0.28), 1.0)
    draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), Color(0.32, 0.48, 0.34, 0.28), 1.0)

    if player == null or not is_instance_valid(player):
        return

    var map_rotation := 0.0
    _draw_world_features(center, radius, map_rotation)
    _draw_enemy_blips(center, radius, map_rotation)
    _draw_player_arrow(center)
    _draw_compass(center, radius, map_rotation)


func _draw_world_features(center: Vector2, radius: float, map_rotation: float) -> void:
    var road_color := Color("#d7a36d")
    _draw_world_segment(center, radius, map_rotation, Vector2(0.0, 594.0), Vector2(world_size.x, 594.0), road_color, 3.0)
    _draw_world_segment(center, radius, map_rotation, Vector2(1108.0, 0.0), Vector2(1108.0, world_size.y), road_color, 3.0)


func _draw_world_segment(
    center: Vector2,
    radius: float,
    map_rotation: float,
    from_world: Vector2,
    to_world: Vector2,
    color: Color,
    width: float
) -> void:
    var from_radar := _world_to_radar(from_world, center, radius, map_rotation, false)
    var to_radar := _world_to_radar(to_world, center, radius, map_rotation, false)
    if from_radar.distance_to(center) > radius and to_radar.distance_to(center) > radius:
        return
    draw_line(from_radar, to_radar, color, width, true)


func _draw_enemy_blips(center: Vector2, radius: float, map_rotation: float) -> void:
    var tree := get_tree()
    if tree == null:
        return

    for node in tree.get_nodes_in_group("meadow_enemy"):
        var enemy := node as MeadowEnemy
        if enemy == null or not enemy.is_alive():
            continue

        var blip := _world_to_radar(enemy.global_position, center, radius, map_rotation, true)
        var blip_radius := enemy.get_radar_blip_radius()
        draw_circle(blip, blip_radius + 1.5, Color(0.05, 0.05, 0.05, 0.85))
        draw_circle(blip, blip_radius, enemy.get_radar_color())


func _draw_player_arrow(center: Vector2) -> void:
    var heading := player.facing.angle() + PI * 0.5
    var points := PackedVector2Array([
        center + Vector2(0.0, -9.0).rotated(heading),
        center + Vector2(7.0, 8.0).rotated(heading),
        center + Vector2(0.0, 4.0).rotated(heading),
        center + Vector2(-7.0, 8.0).rotated(heading),
    ])
    draw_colored_polygon(points, Color("#f4f7ff"))
    draw_polyline(points, Color("#1b2430"), 1.4, true)


func _draw_compass(center: Vector2, radius: float, map_rotation: float) -> void:
    var north := center + Vector2.UP.rotated(map_rotation) * (radius - 12.0)
    var font := ThemeDB.fallback_font
    if font == null:
        draw_circle(north, 3.0, Color("#ffd35c"))
        return
    draw_string(
        font,
        north + Vector2(-5.0, -2.0),
        "N",
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        13,
        Color("#ffd35c")
    )


func _world_to_radar(
    world_position: Vector2,
    center: Vector2,
    radius: float,
    map_rotation: float,
    clamp_to_edge: bool
) -> Vector2:
    var relative := (world_position - player.global_position).rotated(map_rotation)
    var mapped := relative * (radius / RADAR_RANGE)
    var max_offset := radius - 10.0
    if clamp_to_edge and mapped.length() > max_offset:
        mapped = mapped.normalized() * max_offset
    elif mapped.length() > max_offset:
        mapped = mapped.normalized() * max_offset
    return center + mapped
