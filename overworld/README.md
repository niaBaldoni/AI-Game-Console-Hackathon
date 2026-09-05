# Open Meadow

Open Meadow is a lightweight top-down real-time slice for the Arduino Uno Q.
The active game is a 2400×1350 meadow split into four colored lands, with free
joystick movement, a sword on button A, a pause menu on B, and enemies plus
pickups the player can hunt on the radar.

## Controls

Player-facing copy always uses the handheld names:

- Joystick: move in eight directions.
- A: tap to swing; hold then release for a charge spin.
- B: pause (same as C on the board). From the menu, joystick to choose, A to
  confirm. PLAY, RESTART, and QUIT stay mouse-free.

Desktop development still accepts Space as a fallback for button A; that is
not shown on the handheld HUD.

## What is in the meadow now

- **Lands:** Iceland, Fireland, Purpleland, and Grassland, drawn as color
  regions with a north-up radar.
- **Lives:** five hearts at start, longer hurt immunity than the first combat
  pass, and a sixth heart if a pickup is collected while already full.
- **Enemies:** red brutes (melee) and purple mages (fireballs, including a
  charged shot). Neither kind is a boss.
- **Pickups:** pink hearts heal (or add a heart), gold stars grant a short
  power boost (extra swing damage), blue rings grant a short shield (blocks a
  hit). They bob in place and appear as small radar blips.
- **Menus:** title, pause, and defeat screens use retro monospace type with
  outlined gold/ink panels.

## Runtime MCP

Start the game, then run Cursor CLI from this checkout. The project-local MCP
configuration starts `../runtime-mcp/server.py` and exposes:

- `get_game_state` — read the player and active enemy state (including power
  and shield flags when published).
- `set_agent_intent` — publish a bounded opponent intent.
- `spawn_enemy` — request an enemy at bounded meadow coordinates with optional
  health and kind (`brute` or `mage`).

The game remains authoritative: `AgentBridge` validates the request and emits
it, while `OpenMeadow` owns enemy creation, roster limits, and state
publication.

## Arduino Uno Q

The project is configured for the Uno Q Linux side: compatibility rendering,
ETC2/ASTC texture imports, a 960×540 viewport, and the Linux arm64 release
preset in `export_presets.cfg`. Follow `~/summer-uno-q/SKILL.md` for export and
deployment. Do not treat a host boot or export as a finished playtest.

## License and credits

See [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md).
