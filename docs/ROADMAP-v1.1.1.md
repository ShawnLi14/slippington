# v1.1.1 — Map Planning: real traversal heuristics

Scoped 2026-06-12. Motivation: v1.1's landmark maps look right but the
generator's "reachability" is a vertical-gap check that ignores horizontal
distance, walls, and object placement — observed result: springs on
platforms nobody can reach. This release replaces guesswork with a real
traversal model and a validate-and-repair loop.

## 1. Movement graph (the core)

After generating platforms/objects, build a directed graph:
- **Nodes**: standable surfaces (platform tops; the ground split into
  segments where walls/landmarks interrupt it).
- **Jump edges**: from surface A to surface B if the jump arc fits —
  computed from real physics (jump height 126px, horizontal drift from
  PLAYER_SPEED over rise/fall time), evaluated from the nearest takeoff
  point on A, not the platform center.
- **Fall edges**: walking off either edge of A reaches B if B is below
  within horizontal drift (falling is free travel downward).
- **Spring edges**: a spring on A launches to anything within spring
  height (~380px) + drift.
- **Portal edges**: bidirectional pair.
- **Blockers**: an edge is invalid if its straight-line path crosses a
  wall rect or a solid platform's underside at clearance height
  (approximate arc as 3-point polyline: takeoff, apex, landing).
- **Movers**: evaluate their edges at BOTH travel extremes; an edge that
  only exists sometimes counts, but the platform must be reachable at
  some phase and must never sweep through a wall/landmark (separate
  invariant — currently unchecked and likely violated).

## 2. Validate → repair loop (deterministic)

Flood-fill from the ground. For every unreachable surface, repair in
order (using the same seeded RNG stream so maps stay deterministic):
1. Add a stepping platform midway to the nearest reachable surface.
2. Add a spring on the nearest reachable surface below it.
3. Lower the platform toward reachability.
4. Delete it (last resort; also delete objects riding on it).
Bound the loop (e.g. 3 passes), then hard-delete anything still orphaned.

## 3. Object placement rules

- **Springs**: only on reachable surfaces; must have a landing target
  (some surface within launch reach above) and head clearance (no solid
  directly above within launch path). A spring that launches you into a
  ceiling or to nowhere is removed or relocated.
- **Portals**: both endpoints on reachable surfaces; arrival points need
  player-sized clearance (no wall/platform overlap).
- **Movers**: travel sweep must not intersect walls, landmarks, or other
  platforms (with margin); skip the move data if it would.
- **Spawns**: all on the reachable set, pairwise distance >= ~500px.

## 4. Quality heuristics (after correctness)

- **No dead zones**: in each height band, the largest horizontal gap
  between adjacent reachable surfaces <= ~1.5x jump drift; insert a
  connector if exceeded.
- **Route diversity**: the top third of the map reachable via >= 2
  distinct mid-level surfaces (cheap proxy for edge-disjoint paths) so
  one chaser can't guard the only ladder.
- **Landmark margins**: landmarks keep >= 60px from map edges and from
  each other's boxes (towers fusing with pockets creates accidental
  sealed rooms).

## 5. Tests become assertions

`test_mapgen.gd` upgrades from printed warnings to hard failures:
- Run the full validator over ~50 seeds; ZERO unreachable surfaces,
  ZERO invalid objects allowed (exit 1 otherwise).
- Invariant checks for the mover-sweep and portal-clearance rules.
- Determinism double-run stays.

## Files

- new `godot/scripts/map/map_planner.gd` — graph build + flood fill +
  repair + object rules (pure functions over map data; no scene deps so
  headless tests stay light).
- `map_generator.gd` — calls the planner as a post-pass.
- `tests/test_mapgen.gd` — assertion mode over many seeds.

## Out of scope

- Pathfinding for bots (separate concern; would reuse the same graph —
  noted as the future fix for bots getting stuck on walls).
- New landmark types.
