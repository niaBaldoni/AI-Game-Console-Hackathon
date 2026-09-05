# AI Game Console Hackathon

Summer Engine game for Arduino Uno Q. Board and agent rules: [`AGENTS.md`](AGENTS.md).

Playable project: [`overworld/`](overworld/) — **Open Meadow**, a handheld
real-time 2D meadow (joystick, buttons A/B/C).

Current playable loop: walk four colored lands, swing or charge-spin, survive
brutes and mages, find hearts / power / shield pickups, pause from the retro
title menu. Runtime MCP can still read state, set intent, and spawn enemies.

Design history (append-only; do not rewrite old sections when adding features):
[`docs/superpowers/specs/2026-09-05-open-meadow-realtime-design.md`](docs/superpowers/specs/2026-09-05-open-meadow-realtime-design.md)

Scoped soul for the active slice: [`overworld/.summer/GameSoul.md`](overworld/.summer/GameSoul.md)

Player-facing controls and board notes: [`overworld/README.md`](overworld/README.md)

When we change gameplay, **add** to that spec (or `GameSoul.md`) instead of
rewriting earlier sections, unless we are actually replacing that behavior.

![Uploading IMG_0337.jpeg…]()
