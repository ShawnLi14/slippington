# v1.1.0 — "The World Update"

Scoped 2026-06-12. Theme: maps that fight back. Kill the circle-the-platform
stalemate with route asymmetry, commitment cost, and time pressure — plus
sound and rounds.

## Playtest evidence motivating this (bot batch, 16×30s matches)

- **The upper map is dead space**: players spent 0–7% of match time in the
  top 60% of the map. Almost all play happens on the ground floor — the
  procedural maps' verticality is decoration, not gameplay.
- **Chases are bimodal**: a big cluster at 1.5–2.5s (cornered tag-trading at
  immunity expiry — players glued together) and a tail of 9–15s runaway
  chases. Few "good" mid-length chases.
- **Slow-class despair**: Anchor (0.9× speed) as IT against Slipper (1.3×)
  basically never catches — matches with 2–4 total tags where Anchor holds
  IT for 23–28 of 30 seconds. Pure-pursuit maps make speed the only stat.

## Scope

### Map generation 2.0
1. **Landmark-based generator** — split the map into zones; each gets a
   distinct structure (tower with solid walls, overhung pocket with one
   entrance, ice rink, spring yard) connected by reachability-checked
   platforms. First real dead-ends and asymmetric escapes.
2. **Springs** — launch pads that fling players high. Vertical escape from
   orbits; chasers play landing-prediction. Also the slow class's best
   friend (cut off instead of chase).
3. **Ice platforms** — gradual accel/brake on ice; tight reversals become
   commitments. Finally justifies the name.
4. **Moving platforms** — routes that connect/disconnect on a timer; phase
   derived deterministically from the synced match clock.
5. **Portal pairs** — cross-map teleport with per-player cooldown.
6. **Rising slush** — final ~15s, slush floods upward eating the lower map;
   forces endgame convergence (and makes the dead upper map matter).

### Sound pass
Jump, tag (both sides), each ability, spring, portal, countdown ticks,
caught/survived stings, ambient loop. CC0 sources (Kenney audio) or
synthesized.

### Rounds mode
Lobby option: single match (current) or best-of-5. Survivors score a point
per round; running scoreboard between rounds; champion screen at the end.

### Explicitly out (candidates for v1.2)
- Crumbling platforms
- IT speed ramp (decided against — pure equal speeds preserved)
- Class balance changes (watch Anchor with the new maps first; springs +
  portals + stun should close most of the pursuit gap before stats do)

## Order of work
1. Generator restructure + springs + ice (the core)
2. Moving platforms + portals
3. Rising slush
4. Rounds mode
5. Sound pass
6. Full playtest batch + telemetry comparison vs the numbers above; ship
