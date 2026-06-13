Infrastructure release — **TURN relay support**.

## Relay fallback for blocked networks

The signaling server can now hand out a TURN relay alongside STUN. If a direct peer-to-peer connection can't form (VPN, strict campus NAT, filtered UDP on either end), the connection automatically falls back to relaying through the server instead of failing. Direct P2P always wins when it works — the relay only carries traffic for pairs that had no other path, at the cost of a small latency bump for them alone.

This works with existing game builds — the relay config comes from the server, so anyone you play with picks it up automatically without re-downloading. This client build adds one diagnostic: the log now records the ICE configuration each session received (`n STUN / n TURN`), so connection problems can be diagnosed from facts.

The relay is live now (Cloudflare Realtime TURN, verified end to end). If a direct connection isn't possible, the game quietly routes through it instead of failing.

Same join codes. Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → Open the first time.
