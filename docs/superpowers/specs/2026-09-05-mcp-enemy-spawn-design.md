# MCP-controlled enemy spawning design

## Goal

Merge the runtime MCP bridge into the Open Meadow game and let an agent spawn
simple real-time enemies while the game is running. The bridge requests a
spawn; the game remains authoritative over node creation, bounds, health, and
the active enemy list.

## Scope

The first milestone adds one MCP tool, `spawn_enemy`, to the existing
`get_game_state` and `set_agent_intent` tools. It supports bounded explicit
positions and optional health. The game accepts at most eight active enemies
and clamps no values silently: invalid requests return a structured error.

The existing sword attack already targets a single enemy. It will be updated
to search all active `meadow_enemy` group members, so the player can hit both
the initial target and MCP-spawned enemies. The legacy turn-based files remain
in the repository and are not loaded by the active meadow scene.

## Repository integration

The commits from `feat/runtime-mcp` are merged into `main`, preserving the
dependency-free Python stdio server, loopback game client, README, and tests.
The project-level `.cursor/mcp.json` points Cursor at that server. The Godot
bridge is registered as the `AgentBridge` autoload in `project.godot`.

## Runtime architecture

```text
Cursor agent
  -> stdio runtime-mcp/server.py
  -> loopback JSON request
  -> AgentBridge autoload
  -> enemy_spawn_requested(position, health)
  -> OpenMeadow validates and creates MeadowEnemy
  -> get_game_state reports player + active enemies
```

On a desktop, the game bridge accepts the loopback TCP request directly. On an
Uno Q deployment, the game runs inside App Lab's `game_runner` container, so
the bridge also polls `/game/game/.runtime-mcp`. The host-side MCP client maps
that mount to `/home/arduino/ArduinoApps/open-meadow/game/.runtime-mcp` and
exchanges atomically renamed request/response files. This keeps the transport
local to the board without exposing a container port or requiring ad-hoc
board-side Docker configuration.

`AgentBridge` never instantiates gameplay nodes. It validates request shape and
basic meadow coordinate limits, assigns a monotonically increasing request
identifier, emits the request signal, and returns an acknowledgement. The
`OpenMeadow` root handles the signal, enforces the live count and collision-safe
position, creates a `MeadowEnemy`, connects its health/defeat signals, and
publishes the compact observation used by the agent.

## MCP tool contract

### `spawn_enemy`

Arguments:

- `x`: number, inclusive meadow coordinate from 24 to 2376.
- `y`: number, inclusive meadow coordinate from 24 to 1326.
- `health`: optional integer from 1 to 9; defaults to 3.

The bridge rejects missing, non-numeric, non-finite, or out-of-range values and
returns an MCP tool error without emitting a signal. A valid request returns
`queued: true`, the request id, and the normalized position/health. The next
`get_game_state` call must include the spawned enemy once the main game loop
has processed the signal.

## State contract

`get_game_state` returns:

- `player`: position, facing, attacking, and remaining attack cooldown.
- `enemies`: an array of active enemy objects containing a stable runtime id,
  position, health, max health, and alive state.
- `revision`: incremented whenever the bridge publishes a changed summary.

The summary is deliberately compact and JSON-safe. It never serializes the
scene tree or exposes arbitrary node properties.

## Gameplay behavior

`MeadowPlayer` iterates the `meadow_enemy` group during each attack window and
applies damage once per enemy per swing when the target is in range and in the
facing cone. `MeadowEnemy` creates its collision shape when spawned, flashes,
knocks back, emits health/defeat signals, and ignores damage after defeat.

`OpenMeadow` retains one initial target for the visual tutorial and tracks
additional spawned enemies under an `Enemies` container. Defeated enemies are
removed after their feedback window, freeing slots for later spawn requests.

## Safety and failure handling

- The bridge remains bound to `127.0.0.1`; it is not reachable from the LAN.
- Spawn coordinates are validated twice: in the bridge and in `OpenMeadow`.
- A full enemy roster returns `enemy_limit_reached`.
- The game client returns `game_unavailable` when the game is stopped.
- Malformed JSON, oversized messages, invalid tool arguments, and invalid
  health/coordinates cannot crash the game or mutate state.
- No shell, filesystem, arbitrary scene, script, or player-input tool is added.

## Verification

1. Merge the bridge and run the Python MCP unit tests.
2. Run Summer script diagnostics for every bridge, meadow, player, enemy, and
   HUD script.
3. Start Open Meadow and use a `RunVerification` probe to call the game-side
   spawn path, confirm a second enemy appears in `get_game_state`, move toward
   it, and confirm A/Space sword damage changes only that enemy.
4. Spawn eight enemies and confirm the ninth request returns
   `enemy_limit_reached`.
5. Check the running frame and Summer console/debugger for errors or warnings.

## Deferred work

Agent decision-making, enemy pursuit/attacks, spawn waves, persistent enemy
ids across scene changes, remote network transport, and deletion of the legacy
turn-based source remain deferred.

## Update: spawn kinds (5 Sep 2026)

`spawn_enemy` now accepts an optional `kind` of `brute`/`melee` or `mage`/`ranged`.
The game still owns bounds, roster limit, and node creation. If `health` is
omitted, the kind's default HP is used (brute 3, mage 2). Those defaults are
fodder stats, not bosses.

## Update: published player flags (5 Sep 2026)

`get_game_state` player payload also includes `power` and `shield` booleans
when those timed pickups are active. The game still owns timers and combat
math; the MCP tools do not grant pickups.

