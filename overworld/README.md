# Open Meadow

Open Meadow is a lightweight top-down real-time slice for the Arduino Uno Q.
The active game is a large, open meadow with free joystick movement, a short
range sword swing on button A, and enemies that can be spawned and observed by
the runtime MCP bridge.

## Controls

- Joystick: move in eight directions.
- A: swing the sword.

Desktop development also accepts the Space key as a fallback for button A; it
is not part of the handheld-facing HUD.

## Runtime MCP

Start the game, then run Cursor CLI from this checkout. The project-local MCP
configuration starts `../runtime-mcp/server.py` and exposes:

- `get_game_state` — read the player and active enemy state.
- `set_agent_intent` — publish a bounded opponent intent.
- `spawn_enemy` — request an enemy at bounded meadow coordinates with optional
  health.

The game remains authoritative: `AgentBridge` validates the request and emits
it, while `OpenMeadow` owns enemy creation, roster limits, and state
publication.

## Arduino Uno Q

The project is configured for the Uno Q Linux side: compatibility rendering,
ETC2/ASTC texture imports, a 960×540 viewport, and the Linux arm64 release
preset in `export_presets.cfg`. Follow `~/summer-uno-q/SKILL.md` for export and
deployment.

## License and credits

See [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md).
