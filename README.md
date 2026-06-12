# Slippington

Multiplayer 2D platformer tag.

**The game now lives in [`godot/`](godot/)** — a Godot 4.4 rebuild with direct
peer-to-peer connections (WebRTC join codes, ENet for LAN), native Mac and
Windows builds, three classes (Slipper / Bolt / Anchor) with abilities, seeded
procedural maps, and time-as-"it" scoring. See `godot/README.md` to run it.

[`signaling/`](signaling/) is the tiny WebSocket server that brokers the
P2P handshake (join codes + SDP/ICE relay) — no gameplay traffic flows
through it. See `signaling/README.md` for free-tier deploy notes.

The original web prototype (Next.js + Phaser + Supabase Realtime) lives in
[`legacy/`](legacy/) as reference; it synced movement through Postgres,
which is why latency was poor.
