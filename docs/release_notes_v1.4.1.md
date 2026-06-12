Small patch — **you can actually watch your own decoy work now**.

## Decoy

- The clone opens with a short burst of speed, so it visibly splits off from you even when you cast Doppel mid-run. Before, it could sit in perfect lockstep underneath you and the ability looked like a dud on your own screen. (To everyone else — who can't see you at all — the burst just looks like panic sprinting. Good.)
- The clone draws above players, so your faded self never hides it, and it no longer turns around from grazing a corner — only from walls actually in its way.

## Networking

- If a connection can't get through (VPN, strict campus network, filtered UDP), the join screen now tells you so within 20 seconds — *"Connection timed out — a VPN or strict network is likely blocking P2P traffic"* — instead of spinning on "Connecting to host..." forever. Hosts quietly drop joiners whose networks fail, keeping the room alive.

## Under the hood

- New automated test proves Swap is a true position exchange: two clients, 216px apart, cast — both land on the other's exact old spot, 0px error.

Same join codes. Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → Open the first time.
