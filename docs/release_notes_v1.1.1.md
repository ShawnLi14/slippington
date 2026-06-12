Map quality patch: the generator now **proves its maps are playable** instead of hoping.

- Every generated map is validated against a real traversal graph built from actual jump physics — arc height *and* horizontal drift, walls and platform undersides as blockers, plus fall, spring, and portal routes. Anything unreachable gets deterministically repaired (a stepping platform or a spring is added) or removed; same seed still means the same map for everyone.
- Springs can no longer spawn in unreachable spots, under ceilings they'd bonk you into, or with nowhere useful to launch you. Portal exits are checked for player clearance, and moving platforms can no longer sweep through walls.
- Spawn points are guaranteed reachable and spread apart.
- The **Arena** preset got an honest rework: the validator proved its entire upper half was unreachable decoration (and both ground springs launched into shelf undersides). The upper ladder is now a proper stair-step of short hops up to the crown, and the springs moved to the corners.
- The map test suite now hard-fails on any unsound map across 50 seeds + both presets.

Same downloads, same join codes. Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → Open the first time.
