# Open Meadow real-time redesign

## Goal

Replace the active OpenRPG turn-based presentation with a lightweight,
controller-first real-time meadow. The player moves freely with the joystick
and swings a sword with button A. One simple enemy can be hit and defeated in
the meadow.

## Scope

The first playable pass includes:

- A large, open 2D meadow with a small number of readable obstacles and solid
  world boundaries.
- Direct eight-direction player movement using the existing `ui_*` actions.
- A visible sword slash and short-range hitbox on the `attack` action.
- One simple real-time enemy with health, hit flash, knockback, and defeat
  feedback.
- A small, mouse-free HUD that names the joystick and button A.
- Uno Q-safe 2D project settings: 960×540 viewport, compatibility renderer,
  60 FPS cap, and ETC2/ASTC texture support.

The old OpenRPG scene, turn-based combat scripts, arenas, and assets remain in
the repository as legacy reference. They are not loaded by the new main scene
and are not deleted in this pass. Agent/MCP control of the enemy is a later
integration step; this pass provides the real-time enemy state and attack seam
that integration will use.

## Scene architecture

`res://src/realtime/open_meadow.tscn` becomes the project main scene. Its
top-level nodes are:

- `OpenMeadow` (`Node2D`): owns world drawing, boundaries, and the camera.
- `Player` (`CharacterBody2D`): movement, facing, and attack orchestration.
- `Enemy` (`CharacterBody2D`): one damageable target in the central clearing.
- `Obstacles` (`Node2D`): a few `StaticBody2D` rectangles for navigation
  landmarks without closing off the play space.
- `HUD` (`CanvasLayer`): controller instructions, enemy health, and a compact
  hit/defeat message.

The meadow uses a camera that follows the player across a world larger than the
960×540 viewport. The art is intentionally lightweight: existing pixel-art
character textures where compatible, simple drawn grass/paths, and small
procedural shapes for the slash and enemy feedback. No pointer, text entry, or
fourth-button interaction is introduced.

## Movement and attack behavior

The player reads `Input.get_vector("ui_left", "ui_right", "ui_up",
"ui_down")`, normalizes it, and moves at a fixed tunable speed. The last
non-zero direction is the facing direction. Mouse mode is hidden in `_ready`.

The `attack` action is bound to the board's physical A event (J) and joypad
button 0. An attack has a short cooldown and active window. During the active
window, a hitbox in front of the player can hit the enemy once. A slash wedge
is visible for the same window and follows the facing direction. Repeated A
presses during cooldown are ignored rather than queueing extra damage.

The initial enemy is deliberately simple: it stays in the clearing, has three
health points, flashes and is pushed back on a valid hit, then disappears with
a clear defeat state at zero health. Its state is exposed through methods and
signals so a future MCP/agent controller can replace the idle behavior without
changing player combat.

## Turn-based removal

The new main scene contains no `Combat` canvas layer, combat arena instances,
combat trigger transitions, action menus, battler roster, or turn queue. The
legacy `res://src/main.tscn` and `res://src/combat/` tree stay untouched except
where project settings or shared input definitions must be updated. This makes
the active game real-time while preserving an easy rollback path.

## Input and board constraints

The existing arrow/WASD aliases for `ui_*` remain available for development,
but all player-facing instructions use “joystick.” The new attack action uses
button A in copy and J/joypad button 0 in the input map. Buttons B and C are
reserved. All controls work without a mouse, and the mouse cursor is hidden at
runtime.

## Data flow and safety

```text
joystick / A
  -> Player movement or attack state
  -> SwordAttack hitbox + slash visual
  -> Enemy.take_hit()
  -> health / knockback / defeat signal
  -> HUD feedback
```

Attack code validates its target, cooldown, and active window before applying
damage. Enemy damage is idempotent per swing, ignores hits after defeat, and
does not assume optional HUD nodes exist. The scene has no network listener or
arbitrary state mutation; the future MCP bridge can publish or request only
the enemy state seam explicitly exposed by the gameplay scripts.

## Verification

The implementation is complete only after all of these checks pass:

1. Summer script diagnostics report no errors for every new or changed script.
2. A `RunVerification` probe starts the meadow, moves the player by joystick
   actions, presses `attack`, and observes the enemy health decrease; it saves
   start, movement, hit, and defeat frames.
3. The probe repeats attack input during cooldown and confirms it does not
   apply duplicate damage.
4. Summer diagnostics and console contain no new runtime errors after the
   playthrough.
5. The game is visually checked at the 960×540 viewport and later on the Uno
   Q with the physical joystick and button A.

## Deferred work

Agent-controlled enemy decisions, MCP state publication, inventory, map
transitions, and deletion of the legacy turn-based files are intentionally
deferred until this small loop is stable.

## Update: enemy combat (5 Sep 2026)

We kept the meadow, player slash, HUD, and board constraints above. Enemies are
no longer idle dummy targets.

**What changed**

- Enemies face the player when they are in range, then attack.
- Two kinds, still using the existing placeholder shapes:
  - **Melee** — smaller detect range, slow walk, player-like slash, larger HP
    (6).
  - **Mage** — larger detect range, keeps distance, shoots fireballs, smaller HP
    (3).
- Several of both kinds spawn across the meadow (`PACK` in
  `src/realtime/open_meadow.gd`).
- The player now has HP (6) and i-frames; 0 HP is a fall. Fireballs live in
  `src/realtime/meadow_fireball.gd`.
- Radar colors: red melee, purple mage.

Tunables (speed, ranges, fire rate) are first-pass and meant to be iterated.
Original idle-enemy behavior in the sections above is historical.

## Update: brute/mage rebalance and charged fireball (5 Sep 2026)

Neither kind is a boss. Brute HP is 3 and walk speed is 46 (player is 190).
Mage HP is 2 and walk speed is 118, always slower than the player. Mages
sometimes stop and charge a larger fireball (~0.9s, 2 damage); a hit interrupts
the charge. MCP `spawn_enemy` can request `kind` brute or mage.

## Update: pause, title, and defeat menu (5 Sep 2026)

`MeadowPauseMenu` is a mouse-free overlay. Title starts on PLAY. In play, B
opens pause. After defeat, BACK returns to the title instead of dumping the
player into a dead scene. Joystick moves focus; A confirms. Restart reloads
the meadow and skips the title via `MeadowPauseMenu.start_in_game`.

## Update: charge spin (5 Sep 2026)

Tap A remains a directional slash. Hold A past 0.25s, then release, for a
radial spin (2 base damage). Charge slows movement. Design detail lives in
`docs/superpowers/specs/2026-09-05-charge-spin-attack-design.md`. Original
“A is only a short slash” copy above is historical.

## Update: colored lands and HUD hearts (5 Sep 2026)

The meadow is four readable regions (Iceland, Fireland, Purpleland,
Grassland). HUD hearts replaced a numeric-only life readout. Early combat
used three hearts; that count is historical.

## Update: longer lives, pickups, and retro menus (5 Sep 2026)

We kept the meadow combat, radar, pause flow, and board constraints above.

**What changed**

- Player starts at **five hearts**, hurt immunity ~1.05s, cap of six hearts.
- `MeadowPickup` instances spawn across the lands:
  - pink heart: restore one heart, or add a sixth if already full
  - gold star: ~9s power (plus one damage on slash and spin)
  - blue ring: ~7s shield (blocks a hit, short extra immunity)
- Pickups bob with cheap `_draw` circles/arcs; power/shield add a gold wash
  or cyan ring on the player. Radar shows pickup blips.
- Title, pause, HUD labels use a retro system font (Press Start 2P when
  present, else Monaco/Menlo/Courier) plus outlines.

Original deferred-work lines about inventory remain historical; hearts and
boosters are now in the meadow, not a full inventory system.

## Update: smaller fireball hitboxes (5 Sep 2026)

Fireball **sprites stay large** (normal visual radius 8, charged 16). Collision
is smaller so shots are easier to dodge: normal hit radius 3.5, charged 6.5.
Drawn size and hurtbox are independent.
