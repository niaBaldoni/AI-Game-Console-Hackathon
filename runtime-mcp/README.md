# Summer runtime MCP bridge

This package lets Cursor CLI talk to a running Summer/Godot game on the same
Uno Q. Cursor starts `server.py` as a stdio MCP server. The server connects to
the game’s `AgentBridge.gd` over a loopback-only TCP socket.

The first milestone intentionally exposes only two tools:

- `get_game_state` reads the compact state published by the game.
- `set_agent_intent` changes the game-owned opponent intent to `idle`, `left`,
  `right`, or `act`.

There is no shell, filesystem, scene-tree, arbitrary property, or script
execution tool.

## Add it to a Summer project

1. Copy `godot/AgentBridge.gd` into the game project and register it as an
   Autoload named `AgentBridge`.
2. If `runtime-mcp/` lives at the game project root, copy
   `.cursor/mcp.json.example` to the game project as `.cursor/mcp.json`.
   This repository already includes an equivalent project-level config at
   `.cursor/mcp.json`.
3. Start the game. The bridge listens on `127.0.0.1:8765`.
4. From the game project directory, run `agent mcp list` and then
   `agent mcp list-tools summer-runtime`.
5. Ask Cursor to read the game state, then set the agent intent to `left` or
   `right`. Game code can react to the signal:

   ```gdscript
   func _ready() -> void:
       AgentBridge.agent_intent_changed.connect(_on_agent_intent_changed)

   func _on_agent_intent_changed(intent: String) -> void:
       # Map the approved intent to the opponent's gameplay action.
       pass
   ```

Game logic can publish observations without exposing its scene tree:

```gdscript
AgentBridge.publish_summary({
    "score": score,
    "player_hp": player_hp,
    "opponent_hp": opponent_hp,
})
```

## Run the protocol smoke test

The test starts a local mock game bridge, starts the stdio MCP server, lists
the tools, changes the mock opponent intent, and reads the changed revision.
It needs only Python 3:

```sh
python3 -m unittest discover -s runtime-mcp/tests -v
```

The mock proves the MCP and socket contracts; a Summer integration run is
still required to prove the Godot autoload and visible gameplay response.

## Configuration

The server reads these optional environment variables:

- `SUMMER_GAME_MCP_HOST` (default `127.0.0.1`; non-loopback hosts are rejected)
- `SUMMER_GAME_MCP_PORT` (default `8765`)
- `SUMMER_GAME_MCP_TIMEOUT` (default `1.0` seconds)

Keep the project MCP configuration in git. Keep any future credentials outside
the project config and pass them through the board’s persistent environment;
this initial bridge does not require a credential.
