The Terrain Update — **maps stop being flat**.

Until now every surface in Slippington was a flat horizontal rectangle. This release adds a real geometry vocabulary, built on ideas from platformer level-generation research (Spelunky's verified room chunks, Launchpad's component grammars):

- **Ramps.** True angled surfaces you run up and down — including **ice ramps** (a slope you slide on; commit carefully). Every gradient stays walkable.
- **Ground mounds.** The floor itself rolls now: low hills with flat (sometimes icy) crowns rise from the ground between landmarks.
- **The Ridge.** A new landmark — a climbable hill whose crown sits above jump height, so the two ramps *are* the ways up and chases flow over the summit instead of circling a box. There are now five landmark kinds and four columns, so every map is missing a different one.
- **Bent platforms.** Flats can grow a ramp off one end — L-shaped ledges that break up the horizontal monotony.

The map planner verifies all of it with real jump physics, exactly like before: takeoffs and landings are now computed on the incline itself, so every generated map is still provably traversable and bottleneck-free — same seed, same map, for everyone.

Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → Open the first time.
