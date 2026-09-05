# Runtime MCP bridge design

## Goal

Let Cursor CLI running on an Arduino Uno Q inspect a running Summer game and
change a small, game-owned opponent state. This proves an agent-to-game loop
without exposing arbitrary scene mutation, script execution, or a network
service outside the board.

## Scope of the first milestone

The deliverable is a dependency-free `runtime-mcp/` package that a future
Summer project can adopt. It does not create a game or deploy to the Uno Q.

The proof interaction is:

1. The agent calls `get_game_state`.
2. The agent calls `set_agent_intent` with one allowed intent.
3. A subsequent `get_game_state` returns that changed intent and a higher
   revision number.
4. The running game receives a signal for the changed intent and may map it to
   opponent behaviour.

## Architecture

```text
Cursor CLI agent
  -> stdio MCP server (Python standard library)
  -> newline-delimited JSON over TCP, 127.0.0.1 only
  -> AgentBridge.gd autoload in the running Summer game
  -> opponent/gameplay logic
```

Cursor starts the MCP server through a project-level `.cursor/mcp.json`
configuration. The MCP process accepts protocol traffic only on standard input
and output. The Godot bridge accepts one request per TCP connection on the
loopback interface, so it is unreachable from the LAN and the physical game
controller remains the only player-facing input.

## Public MCP tools

### `get_game_state`

Returns a JSON object containing:

- `agent_intent`: the current approved opponent intent.
- `revision`: a monotonically increasing counter, incremented whenever the
  intent changes.
- `summary`: an optional JSON-safe state object supplied by the game.

The bridge supplies an empty summary by default. Game code may explicitly
publish a compact summary such as score, player position, and opponent
position; it must not automatically serialize the scene tree.

### `set_agent_intent`

Accepts exactly one `intent` from this initial allow-list:

- `idle`
- `left`
- `right`
- `act`

On success it changes `agent_intent`, increments `revision`, emits
`agent_intent_changed(intent)`, and returns the resulting state. Invalid values
are rejected without changing state.

## Components

`runtime-mcp/` will contain:

- `server.py`: a stdio MCP server built only with Python's standard library.
- `game_client.py`: strict, timeout-bounded client for the loopback bridge.
- `godot/AgentBridge.gd`: Godot autoload which owns published state and emits
  the gameplay signal.
- `.cursor/mcp.json.example`: Cursor project configuration that starts the
  local server with `python3`.
- `tests/`: a mock bridge plus protocol tests for MCP discovery, reading state,
  changing an allowed intent, and rejecting an invalid intent.
- `README.md`: installation, game integration, verification, and security
  boundary instructions.

## Error handling and safety

- The bridge binds only to `127.0.0.1` and uses a fixed local port configurable
  in one place.
- The MCP client has a short connection/read timeout and returns a structured
  `game_unavailable` error when the game is not running.
- Requests and responses have a small maximum size; malformed JSON returns an
  error and cannot terminate the game.
- The bridge exposes no filesystem, shell, scene-tree, or arbitrary property
  access.
- The MCP server emits protocol messages only to stdout; diagnostic logs go to
  stderr.

## Validation

Unit tests run the MCP process against a local mock bridge and assert the tool
contract. When a Summer project is available, an integration check will add
`AgentBridge.gd` as an autoload, run the game, and use Cursor's MCP discovery
to invoke `set_agent_intent`. The visible game and a follow-up
`get_game_state` response must both show the changed value.

## Deferred work

The first milestone intentionally excludes autonomous startup, remote network
access, screenshots, player input injection, model inference, deployment, and
any non-allow-listed game mutation. Those can be added after the local
opponent-state loop has been proven on the Uno Q.
