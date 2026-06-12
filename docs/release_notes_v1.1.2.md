Map flow patch — **no more bottlenecks**.

- The map planner now enforces **2-connectivity**: every surface must stay reachable from the ground even if any single other surface were removed. In tag terms: there is never an "only ladder" a chaser can guard — every region of every map has at least two independent ways in. The planner detects cut-vertex chains and repairs them (adding alternative routes via stepping platforms or aimed springs) until the property holds, deterministically per seed.
- **Minimum platform width raised 120 → 180px** (+50%) — generated maps feel less like tightropes.
- The hand-built Arena and Towers presets now run through the same planner pipeline with a fixed seed: the validator proved Arena's central stage alone gated 8 surfaces, so the planner augments hand-made layouts too.
- The map test gate now also fails on any bottleneck, across 50 seeds + both presets.

Same downloads, same join codes.
