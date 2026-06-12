**Multiplayer platformer tag over direct peer-to-peer connections.** One player is IT; touch someone to pass it on; the first tag starts a 60-second clock — whoever is holding the tag at zero is CAUGHT, everyone else survives.

![gameplay](https://raw.githubusercontent.com/ShawnLi14/slippington/main/docs/gameplay.png)

## Download & run
- **Windows**: `Slippington-Windows.zip` — unzip, run `Slippington.exe` (keep the .dll next to it). SmartScreen: *More info → Run anyway*.
- **macOS** (Intel + Apple Silicon): `Slippington-macOS.zip` — unzip, **right-click** `Slippington.app` *→ Open → Open* the first time (unsigned app). If macOS only offers "Move to Trash": *System Settings → Privacy & Security → Open Anyway*.

## Play online in 10 seconds
One player clicks **CREATE GAME** and shares the 5-letter code (COPY button in the lobby). Friends enter it, **JOIN**, pick a class, ready up. Game traffic is peer-to-peer — the host's machine referees the match; no accounts or setup. LAN/direct-IP play is under the *advanced* toggle.

## What's in the box
- **3 classes** — Slipper (**Blink**: teleport ahead), Bolt (**Swap**: trade places with the nearest player), Anchor (**Stun Pulse**: freeze everyone nearby). Q to use, switchable in the lobby.
- **Procedural maps** from shared seeds plus two hand-built arenas (Arena, Towers), with drop-through platforms and animated themed backdrops.
- **Survivor scoring** with a ranked end screen, instant rematch, random first IT, and a tag-back immunity window.
- **Netcode built for fairness over home internet**: 60 Hz replication with sender-timeline snapshot interpolation and adaptive jitter buffering; tagger-side hit detection with host lag-compensated validation (250 ms rewind cap) so tags land when the chaser sees them land.

## Known limitations
- ~5–10% of player pairs (both behind strict NATs) can't connect directly — the game says so clearly; use Direct Connect on LAN or have a different player host.
- Unsigned builds (hence the SmartScreen/Gatekeeper steps above).
- Match telemetry is logged locally to `user://match_history.jsonl` on the host (used for balance tuning; nothing leaves your machine).
