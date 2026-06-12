The Terrain Update — **maps stop being flat**.

Until now every surface in Slippington was a flat horizontal rectangle. This release adds a real geometry vocabulary, built on ideas from platformer level-generation research (Spelunky's verified room chunks, Launchpad's component grammars):

- **Angled platforms.** Normal-thickness platforms tilted at slight, varying angles — run up them, slide down them, and yes, some of them are **ice**. Flats can also grow a **bent end**: an L-shaped ledge rising off one side.
- **The Mast.** A new landmark: one tall spine with platforms sticking out across it — two parallel ladders sharing a divider. The sides connect under the base and over the crow's nest at the top; mid-climb the spine blocks horizontal moves, so the play is the feint — start up one side, drop through, slip under the base, climb the other. There are now five landmark kinds and four columns, so every map is missing a different one.

The map planner verifies all of it with real jump physics, exactly like before — takeoffs and landings are computed on the incline itself, and arcs now consider side approaches (so structures like the mast verify honestly). Every generated map is still provably traversable and bottleneck-free — same seed, same map, for everyone.

Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → Open the first time.
