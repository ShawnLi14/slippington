# Slippington signaling server

Tiny WebSocket server that brokers WebRTC connections between players:
rooms keyed by 5-letter join codes, relaying SDP offers/answers and ICE
candidates. **No gameplay traffic flows through it** — once peers connect
directly it's idle. No database, no auth, in-memory rooms only.

## Run locally

```
npm install
npm start          # listens on ws://0.0.0.0:9080 (PORT env to change)
```

## Deploy (free tier friendly)

Any Node host works — Fly.io, Railway, a $0 VPS. One process, ~30 MB RAM.

- Set `PORT` if the platform assigns one.
- Put it behind a TLS proxy and use `wss://` in production — some networks
  interfere with plain `ws://`. (Fly/Railway terminate TLS for you; point
  the game at `wss://your-app.fly.dev`.)
- To add a TURN relay later (for the ~5-10% of strict-NAT pairs that can't
  connect directly), run coturn and add its URL + credentials to the
  `ICE_SERVERS` array in `server.js`. No game-side changes needed.

## Protocol

Client → server: `{type:"host"}` · `{type:"join", code}` ·
`{type:"offer"|"answer"|"candidate", to, data}` · `{type:"leave"}`

Server → client: `{type:"hosted", code, peer_id:1, ice_servers}` ·
`{type:"joined", peer_id, host_id:1, ice_servers}` · `{type:"peer_joined", peer_id}` ·
`{type:"peer_left", peer_id}` · relayed `offer/answer/candidate` with `from` ·
`{type:"error", reason}`

Peer IDs are Godot multiplayer IDs: host is always 1, joiners get 2, 3, ...
Rooms close when the host disconnects and expire after 30 minutes idle.
