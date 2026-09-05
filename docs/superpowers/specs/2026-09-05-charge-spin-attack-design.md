# Charge Spin Attack

**Date:** 2026-09-05  
**Project:** Open Meadow  
**Status:** Design approved

## Goal

Extend the existing A-button sword swing with a retro Zelda-style charged
spin. A quick tap preserves the current directional attack; holding A prepares
a stronger radial attack that fires when A is released.

## Input and state flow

The existing `attack` action remains the only gameplay input. It is already
bound to the handheld controller's A button, with keyboard aliases retained for
development only.

1. On A press, begin a pending attack if the player is alive and the attack
   recovery timer is clear.
2. If A is released before `spin_charge_threshold` (0.25 seconds), perform the
   existing forward sword swing for 1 damage.
3. Once A has been held for at least 0.25 seconds, enter the charged state.
   While charged, joystick movement remains available at 45% of normal speed;
   joystick direction continues to update facing.
4. On A release from the charged state, perform one 360-degree spin for
   2 damage.

The exact threshold boundary counts as charged. An attack pressed during
recovery is ignored and is not queued. Defeat cancels any pending charge.

## Response and combat rules

The quick attack keeps its current duration, reach, directional cone, and
one-hit-per-enemy behavior.

The spin attack is a separate active attack mode. It checks all living meadow
enemies within `spin_attack_reach` (68 pixels), ignores facing, and records
each hit target so an enemy can only be damaged once per spin. The spin lasts
`spin_attack_duration` (0.30 seconds) and uses `spin_attack_cooldown` (0.52
seconds) for recovery. It does not grant invulnerability or otherwise change
the player's damage rules.

## Feedback

Feedback is visual-only because the current meadow has no audio layer.

- While A is held, the player shows a small charge indicator. After the
  threshold, the indicator becomes a bright gold ring that makes the charged
  state clear without a HUD explanation.
- The spin draws a full radial gold slash around the player during its active
  window.
- The existing HUD message channel shows `CHARGE SPIN` when the threshold is
  crossed and `SPIN ATTACK` when the release fires the spin. A quick tap keeps
  the existing `SWORD SWING` message.
- The player's reduced movement during charge is the mechanical feedback that
  the attack is being prepared and carries risk.

## Failure modes and depth

- Release before the threshold: quick swing, never a partial spin.
- Release after the threshold: one spin, even if the button is held longer.
- Press during recovery: no attack and no delayed release attack.
- Press after defeat or release after defeat: no attack.
- Enemies outside the spin radius are unaffected.
- An enemy already hit by the spin cannot be hit again until a later attack.

The player chooses between a safe, fast, directional 1-damage swing and a
slower, movement-limited charge that can deal 2 damage to every nearby enemy.
That creates a clear risk/reward decision for enemy groups without adding a
new button or a pointer interaction.

## Tunables

The following values remain inspector-editable in `MeadowPlayer`:

```text
spin_charge_threshold = 0.25 seconds
spin_move_speed_multiplier = 0.45
spin_attack_damage = 2
spin_attack_reach = 68 pixels
spin_attack_duration = 0.30 seconds
spin_attack_cooldown = 0.52 seconds
```

Existing quick-attack tunables are unchanged.

## Architecture

No new scene nodes or assets are required.

```text
OpenMeadow
├── Player (CharacterBody2D, MeadowPlayer)  MODIFY attack input/state/draw
│   ├── CollisionShape2D                    existing
│   └── Camera2D                             existing
└── HUD (CanvasLayer, MeadowHud)             MODIFY existing signal messages
```

`MeadowPlayer` owns the pending, charged, quick, and spin states. It exposes
the charge/attack state through its existing state-reporting method so runtime
inspection remains truthful. `OpenMeadow` only translates the player's attack
signals into the existing HUD message channel.

## Verification plan

Use a real runtime probe after implementation to verify:

1. A short press/release produces a directional attack and 1 damage.
2. Holding A past the threshold slows movement while charging and produces no
   damage before release.
3. Releasing a charged A produces a spin, deals 2 damage to multiple nearby
   enemies, and does not require facing them.
4. Each enemy is damaged at most once per spin.
5. Pressing during recovery does not queue a second attack.
6. Repeating quick and charged attacks across several physics frames leaves no
   stale charge or hit-target state.

The final check must include a played game walkthrough and fresh diagnostics;
static script checks alone are insufficient for this input-driven mechanic.

## Out of scope

This pass does not add sound, new controller buttons, invulnerability, enemy
AI changes, new animation assets, or new scene nodes.
