Breathing-room patch — **maps with real gaps, structures built for juking, HUD that gets out of the way**.

- **The walled tower is gone.** Its shelves were meant to force weaving but could come out as an E-shaped trap — go in, get cornered. In its place: a **zigzag scaffold** — four stacked storeys with alternating overhangs where every floor below the crown is passthrough. Drop through it, jump up through it, fake one and take the other: nothing inside can corner you, and chases through it become pure mixups.
- **Every platform material now comes in two variants**: the normal one, and a transparent one-way version you can jump up through (and deliberately drop through with down+jump). The old green "passthrough" type is gone — transparent black, transparent *ice* (slippery and one-way, good luck), all with a bright dashed top edge so you can read them at speed.
- **Minimum platform gap is now 100px** (2.5 player widths), between neighboring platforms *and* between every platform and the map border. No more near-touching ledges that read as one broken floor — layouts are islands with clean drop channels, and nothing hides flush against the edge of the world. Moving platforms respect it too: a patrol route that would sweep into the border zone gets grounded.
- The map test gate now hard-fails any generated platform (or mover travel range) inside the border gap, across all 50 validation seeds — this rule can't silently regress.
- **The ability HUD is now translucent** so you can watch the map through it.

Generated maps reshuffle with this patch (same seed still means the same map for everyone). Same downloads, same join codes.
