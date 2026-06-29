# Slippington (Godot rebuild)

Multiplayer 2D platformer tag, rebuilt in **Godot 4.4.1-stable** with direct
peer-to-peer connections (WebRTC) between players.

## Requirements

- **Godot 4.4.1-stable** exactly — export templates and the bundled WebRTC
  extension are version-sensitive. Download: https://godotengine.org/download/archive/4.4.1-stable/
- The [webrtc-native GDExtension](https://github.com/godotengine/webrtc-native)
  v1.1.0 is committed into this folder (`webrtc/` + `webrtc.gdextension`).
  Without it, online (code-based) play is disabled but LAN/direct-IP still works.

## Run

Open this folder in the Godot editor and press F5, or:

```
godot --path .   # with godot 4.4.1 on PATH
```

Two-instance local test: Debug > Run Multiple Instances in the editor, or
launch the binary twice and use Direct Connect with IP `127.0.0.1`.

## Playing online (join codes)

1. The game points at the deployed signaling server by default
   (`wss://slippington-signaling.fly.dev`). For local testing you can
   override the URL in the menu (`cd ../signaling && npm start` runs one
   on `ws://127.0.0.1:9080`).
2. Click **CREATE GAME** and share the 5-letter code.
3. Friends enter the code and click **JOIN**. Game traffic flows directly
   between players (the signaling server only brokers the handshake).

If a connection fails ("connection blocked by network"), both players are
likely behind strict NATs — use Direct Connect with a port-forwarded host,
or play on the same LAN.

## Architecture (short version)

- **Per-peer movement authority**: your machine simulates your own player —
  zero input latency. Positions replicate at 60 Hz over unreliable channels;
  remote players render 75 ms in the past via snapshot interpolation.
- **Tagger-side hit detection**: the "it" player's client decides when
  contact happens (its true position vs. the puppets it sees), so tags land
  exactly when the chaser sees them; the host validates each claim
  (right claimant, immunity, plausible distance).
- **Host-authoritative rules**: the hosting player's machine referees tags,
  the 60s match timer, the survivor scoring (whoever is "it" at zero loses,
  everyone else wins) and validates ability cooldowns.
- **Transports**: `WebRTCMultiplayerPeer` (star topology, host = peer 1) for
  online play; `ENetMultiplayerPeer` for LAN/direct IP. All game code is
  transport-agnostic Godot high-level multiplayer (RPCs).

## Tests

Map generation must be deterministic across platforms (same seed → same map
on every client). Verify on each OS and diff the output:

```
godot --headless --path . --script res://tests/test_mapgen.gd
```

Full multiplayer integration test (two headless bot instances play a real
match: connect, lobby, tag, abilities, scored finish). Run in two terminals:

```
godot --headless --path . -- --auto=host --port=7799 --match-seconds=8
godot --headless --path . -- --auto=join --port=7799
```

Same over WebRTC + signaling (start `npm start` in ../signaling first):

```
godot --headless --path . -- --auto=host-online --code-file=/tmp/code.txt --signaling=ws://127.0.0.1:9080 --match-seconds=8
godot --headless --path . -- --auto=join-online --code-file=/tmp/code.txt --signaling=ws://127.0.0.1:9080
```

Each instance prints PASS/FAIL per check and exits 0 only if all pass.

Version / update-check unit tests:

```
godot --headless --path . --script res://tests/test_version.gd
```

Version-gate + auto-update swap-engine driver tests (headless):

```
godot --headless --path . -- --auto=host-idle --port=7811
godot --headless --path . -- --auto=join-badversion --port=7811 --force-version=9.9.9
godot --headless --path . -- --auto=update-dryrun
```

## Releasing — version bump

`GameConfig.GAME_VERSION` (`scripts/game/constants.gd`) is the single source of
truth for the version label, the join gate, and the auto-update check. **Before
every release, bump it** and keep `export_presets.cfg`'s macOS
`application/version` / `application/short_version` in sync. A forgotten bump
makes the new build reject same-release joiners and never see itself as "up to
date". The git tag (`vX.Y.Z`) must match `GAME_VERSION` (`X.Y.Z`).

**Auto-update scope (Windows):** the Windows auto-update swaps only the
executable(s) (`Slippington.exe` / `Slippington.console.exe`); it does NOT
replace sidecar native libraries such as the bundled `webrtc` DLL. For an
ordinary content release the DLL is byte-identical, so this is invisible — but
a release that updates the `webrtc`/`godot-cpp` GDExtension must be shipped as a
manual full-zip download (don't rely on auto-update for it), or online play will
break on a partially-updated install. macOS is unaffected: it swaps the whole
`Slippington.app`, framework included.
