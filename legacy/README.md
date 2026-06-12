# Legacy web prototype

The original Slippington: Next.js + React + Phaser 3, with lobbies in
Supabase and movement synced through Supabase Realtime (`postgres_changes`
on a `players` table). `server/` holds an experimental authoritative
WebSocket server that was never fully integrated.

Kept for reference only — the game was rebuilt in Godot (see `../godot/`)
because routing movement updates through Postgres added far too much
latency. The game design (classes, abilities, seeded map generation, tag
rules) was ported from here.

To run it anyway: `npm install && npm run dev` (needs Supabase env vars in
`.env.local`).
