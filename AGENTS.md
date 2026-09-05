# Summer Engine × Arduino Uno Q

This workspace is for a **Summer Engine game targeting an Arduino Uno Q**.
The canonical hardware/build/deployment baseline is
[`SummerEngine/summer-uno-q`](https://github.com/SummerEngine/summer-uno-q).
Read its `README.md` before creating or reconfiguring a project, and follow its
`SKILL.md` verbatim when deploying. This file records the durable project
context; the upstream repository remains the source of truth when it changes.

## Target and constraints

- The game runs on the Uno Q's Linux side (Qualcomm QRB2210 with an Adreno 702
  mobile GPU), **not** on the microcontroller. The deployment target is Linux
  `arm64` / `aarch64`.
- Design for the fixed physical controller: a joystick plus buttons **A**, **B**
  and **C**. Hardware events arrive as `W/A/S/D` and `J/K/L` respectively, but
  player-facing copy, tutorials, HUDs, menus, and agent messages must name the
  joystick and buttons A/B/C—not keyboard keys.
- Every screen, including title, pause, game-over, and settings, must be fully
  usable without a mouse. Bind `W/A/S/D` and arrow-key aliases to Godot's
  `ui_*` actions; bind `J` to `ui_accept`; focus the first actionable control
  when a menu appears. Hide the mouse cursor in code with
  `Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)`.
- Treat this as a handheld game from the first design decision. Do not add a
  mechanic, menu, or interaction that needs a pointer, text entry, or a fourth
  button.

## Discover before changing anything

1. Inspect the existing workspace before scaffolding or overwriting files.
2. Detect the Summer installation with:

   ```sh
   npx -y summer-engine@latest doctor --json
   ```

3. Run Summer's setup for the active host (`setup codex`) even when `doctor` is
   green. A green doctor does not prove this agent session has loaded Summer's
   MCP tools.
4. Prove the MCP connection with the harmless `summer_is_running` tool. If the
   tool is unavailable, tell the user to restart the Codex/editor host; do not
   hand-author scenes or fabricate tool results in its absence. Once a project
   is open, wait until `summer_get_project_context` can see it before building.
5. Ask what game the user wants before creating a project. Suggest a Summer
   template only when it fits and wait for their choice. Create with
   `npx -y summer-engine@latest create <template-or-empty> <name>`.
6. After the project exists, run the `brainstorm-game` workflow to write the
   scoped design in `.summer/GameSoul.md` before substantive implementation.

Do not assume the engine, MCP connection, export templates, `adb`, a board, or
the deployment kit are installed merely because this guide describes them.
Detect what is present and install or request only what is missing.

## Current project state (5 Sep 2026)

- The active project is [`overworld/`](overworld/). Its main scene is
  `res://src/realtime/open_meadow.tscn` (`Open Meadow`), a 2400×1350 2D meadow
  with four colored lands, free movement, tap-A slash and hold-A charge spin,
  melee brutes and mage fireballs, five starting hearts, map hearts plus
  power/shield pickups, a north-up radar, and a retro title/pause/defeat menu.
  Player-facing controls are **joystick to move, A to swing/spin, B to pause**.
- The turn-based OpenRPG template is no longer part of the active build. Its
  legacy Dialogic/combat/field assets were intentionally removed; the safety
  branch `main-pre-legacy-cleanup` retains the pre-cleanup tree if historical
  comparison is needed.
- Runtime MCP lives in `runtime-mcp/` and is copied into
  `overworld/runtime-mcp/` for export. `AgentBridge` is an autoload, and the
  stdio server exposes `get_game_state`, `set_agent_intent`, and `spawn_enemy`.
  On release, the game self-seeds the server, Cursor rule, and `.cursor/mcp.json`
  into the App Lab mount, so a source checkout is not needed on the board.
- The Uno Q Cursor CLI does not expand `${workspaceFolder}` in stdio arguments.
  The release-generated config therefore uses the absolute server path
  `/home/arduino/ArduinoApps/open-meadow/game/runtime-mcp/server.py` and the
  shared bridge directory
  `/home/arduino/ArduinoApps/open-meadow/game/.runtime-mcp`. Run Cursor from
  `/home/arduino/ArduinoApps/open-meadow/game`, approve the server with
  `agent mcp enable summer-runtime`, then inspect it with
  `agent mcp list-tools summer-runtime`.
- `origin/main` tracks the current Open Meadow slice (pause menu, charge spin,
  lands, longer lives, pickups, retro menus, and MCP path fix). Editor-local
  `overworld/project.godot` rewrites that drop `import_etc2_astc` must not be
  committed. The board may still be on an earlier export; re-export and
  redeploy before claiming the latest gameplay is on hardware.
- Verified on the host: a clean Summer headless import for the pickup scripts
  and all three tests in `runtime-mcp/tests` pass. A connected-display,
  physical-controller playtest is still required before calling the device
  delivery complete.

## Required project configuration

Apply this immediately after project creation, before adding project-specific
content. It is board configuration, not a user-facing design decision.

In `project.godot`:

```ini
[application]
run/max_fps=60

[display]
window/size/viewport_width=960
window/size/viewport_height=540
window/stretch/mode="viewport"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
```

- Never leave the project on `forward_plus` and never enable `msaa_3d`.
- 960×540 is the maximum design/render resolution. Pixel-art projects may use
  480×270, or render their world at half resolution through a SubViewport while
  retaining a crisp UI.
- For 3D projects only, add this profile under `[rendering]`:

  ```ini
  lights_and_shadows/directional_shadow/size=1024
  lights_and_shadows/directional_shadow/soft_shadow_filter_quality=0
  scaling_3d/mode=0
  scaling_3d/scale=0.7
  shading/overrides/force_vertex_shading=true
  ```

- Do not add `mobile` to an export preset's `custom_features`: it makes games
  that check `OS.has_feature("mobile")` select touchscreen controls.
- If `import_etc2_astc` was added to a project that already had assets, force a
  reimport before export:

  ```sh
  "<engine>" --headless --path "<project>" --import
  ```

## Export preset

Maintain a Linux arm64 release preset in `export_presets.cfg`. Preserve existing
presets and use the next free numeric index consistently for both sections.

```ini
[preset.N]
name="Linux arm64 (Uno Q)"
platform="Linux"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/game-linux-arm64.zip"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.N.options]
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
binary_format/architecture="arm64"
texture_format/s3tc_bptc=false
texture_format/etc2_astc=true
ssh_remote_deploy/enabled=false
```

The required characteristics are `architecture="arm64"`, ETC2/ASTC enabled,
S3TC/BPTC disabled, and `embed_pck=false` (the App Lab installer needs a
separate `.pck`). Export **release**, never debug, to
`build/game-linux-arm64.zip`; create `build/` first and verify the export exits
successfully *and* produced a freshly modified zip. Keep `build/` ignored by
version control.

## Deployment boundary — no improvised hardware commands

Deploy only when the user asks to put, update, or run the game on the Uno Q.
The deployment runbook and its scripts are the sole authority for board-side
work:

```text
~/summer-uno-q/SKILL.md
~/summer-uno-q/board/
```

If that checkout is not present, clone `https://github.com/SummerEngine/summer-uno-q`
to `~/summer-uno-q` (or another stable absolute location) before deployment and
update this pointer if a different location is deliberately used. Do not use a
temporary checkout.

Never improvise `adb`, Docker, SSH, `apt`, manual App Lab assembly, or board
repair commands. The upstream `SKILL.md` controls board provisioning, export,
install, input bridging, troubleshooting, and teardown. It also requires the
project path plus a user-chosen App Lab game name and emoji for every deploy;
ask for the name and emoji together before exporting unless the user explicitly
supplied both.

- First-time provisioning has an interactive `sudo` prompt. Give the user the
  runbook command to execute in *their own terminal* and never request their
  password.
- A direct data USB-C cable is required. Check/poll for the board rather than
  treating its first-minute boot time as a failure.
- The first deployment can take several minutes to compile/flash the input
  bridge; a 3D game's first launch can take another minute for shader setup.
- A successful command is not a playtest. The game is done only after it has
  been played on a connected display with the physical controller.

## Performance and asset guardrails

- `gl_compatibility`, the display cap, and ETC2/ASTC are required baseline
  settings, not temporary fallbacks.
- If a 3D scene containing `.glb`/`.gltf` meshes uses shadow-casting Omni or
  Spot lights, set `meshes/create_shadow_meshes=false` on those imports to
  avoid GLES material-error spam and severe slowdown.
- Texture compression, mipmaps, and size limits reduce transfer size and memory
  use; they do not cure a frame-rate problem. Measure before tuning; diagnose
  fill/shading, draw calls/overdraw, and per-frame scripting separately.
- Do not claim a frame rate from a cap or settings change. Report what was
  configured or measured on actual hardware.

## Communication and completion

- Keep the user informed only about decisions, changes, blockers, and results;
  do not narrate routine clean checks or dump engine/container logs.
- Be warm and concise. One natural ☀️ is welcome in a deployment handoff or
  success message; accuracy comes first.
- On successful deployment, say the game is on the board and describe its
  controls using joystick/A/B/C. Do not tell the player to press W/A/S/D/J/K/L.
- Do not call a feature or game complete based solely on static checks, a clean
  export, or editor play. For Uno Q delivery, require the physical-board
  playtest described above.
