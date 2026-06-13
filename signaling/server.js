// Slippington signaling server.
//
// Brokers WebRTC connections between a game host and joiners: rooms keyed by
// short join codes, relays SDP offers/answers and ICE candidates. Carries no
// gameplay traffic — once peers connect directly, this server is out of the
// loop entirely.
//
// Run: npm install && node server.js   (PORT env var, default 9080)

const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 9080;
const MAX_PLAYERS = 8;
const ROOM_IDLE_TIMEOUT_MS = 30 * 60 * 1000;
// Unambiguous code alphabet: A-Z minus I/O, digits 2-9.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// --- ICE servers ------------------------------------------------------------
// STUN is always handed out. TURN relay (for peers whose networks block
// direct P2P) comes from either of two optional configs:
//   Static (coturn, Metered, ...):  TURN_URLS=turn:host:3478,turns:host:5349
//                                   TURN_USERNAME=... TURN_CREDENTIAL=...
//   Cloudflare Realtime TURN:       CF_TURN_KEY_ID=... CF_TURN_API_TOKEN=...
//     Credentials are minted on demand with a 24h TTL and re-minted after 6h,
//     so clients always receive creds with >=18h of validity — comfortably
//     longer than any game session, since a relayed game dies if its TURN
//     credentials expire mid-match.
// With neither set, clients get STUN-only (the pre-TURN behavior).
const STATIC_ICE = [
  { urls: ['stun:stun.l.google.com:19302'] },
  { urls: ['stun:stun1.l.google.com:19302'] },
];
if (process.env.TURN_URLS) {
  STATIC_ICE.push({
    urls: process.env.TURN_URLS.split(',').map((u) => u.trim()),
    username: process.env.TURN_USERNAME || '',
    credential: process.env.TURN_CREDENTIAL || '',
  });
  console.log(`static TURN configured: ${process.env.TURN_URLS}`);
}

const CF_TTL_SEC = 24 * 3600;
const CF_REMINT_MS = 6 * 3600 * 1000;
let cfCache = { servers: [], mintedAt: 0 };

// Applied only to native (libjuice) clients; browser clients bypass this and
// get the full list (see iceServersForClient). Godot's webrtc-native (libjuice)
// supports TURN over UDP only — it logs "TURN transports TCP and TLS are not supported" and
// floods CreatePermission errors when handed turn?transport=tcp / turns:.
// Cloudflare advertises 6 TURN URLs (4 of them TCP/TLS); strip those so the
// client only ever sees usable relays. (Verified separately: the UDP relay
// allocates, permits, and forwards data end to end.) STUN urls pass through
// untouched. The ceiling this leaves: a network that blocks UDP entirely
// can't be rescued, since TCP/TLS relay isn't available in this stack.
function udpOnlyTurn(servers) {
  return servers
    .map((s) => {
      const urls = (Array.isArray(s.urls) ? s.urls : [s.urls]).filter((u) => {
        if (u.startsWith('turns:')) return false; // TLS relay — unsupported
        if (u.startsWith('turn:')) return u.includes('transport=udp');
        return true; // stun: and anything else
      });
      return { ...s, urls };
    })
    .filter((s) => s.urls.length > 0);
}

// allowTcpRelay: browser clients support turns:/TCP relays and need them on
// UDP-blocked networks, so they get the unfiltered list. Native (libjuice)
// clients are UDP-relay only and get the udpOnlyTurn()-filtered list. Defaults
// to false so older native clients that send no flag keep the UDP-only behavior.
async function iceServersForClient(allowTcpRelay = false) {
  const servers = [...STATIC_ICE];
  const keyId = process.env.CF_TURN_KEY_ID;
  const token = process.env.CF_TURN_API_TOKEN;
  if (keyId && token) {
    try {
      if (Date.now() - cfCache.mintedAt > CF_REMINT_MS) {
        const resp = await fetch(
          `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate-ice-servers`,
          {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ ttl: CF_TTL_SEC }),
          }
        );
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const data = await resp.json();
        // Endpoint returns { iceServers: [...] } (older variant: a single object).
        const minted = Array.isArray(data.iceServers) ? data.iceServers : [data.iceServers];
        cfCache = { servers: minted, mintedAt: Date.now() };
        console.log('minted Cloudflare TURN credentials');
      }
      servers.push(...cfCache.servers);
    } catch (e) {
      // STUN-only beats no answer: never let a TURN hiccup block a session.
      console.log(`cloudflare TURN mint failed: ${e.message}`);
    }
  }
  return allowTcpRelay ? servers : udpOnlyTurn(servers);
}

const rooms = new Map(); // code -> { host, peers: Map<peerId, ws>, nextPeerId, lastActivity }

function makeCode() {
  let code;
  do {
    code = Array.from({ length: 5 }, () =>
      CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]
    ).join('');
  } while (rooms.has(code));
  return code;
}

function send(ws, msg) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

const wss = new WebSocketServer({ port: PORT });
console.log(`Slippington signaling server listening on :${PORT}`);

wss.on('connection', (ws) => {
  ws.roomCode = null;
  ws.peerId = null;

  ws.on('message', async (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const room = ws.roomCode ? rooms.get(ws.roomCode) : null;
    if (room) room.lastActivity = Date.now();

    switch (msg.type) {
      case 'host': {
        if (ws.roomCode) return;
        const code = makeCode();
        rooms.set(code, {
          peers: new Map([[1, ws]]),
          nextPeerId: 2,
          lastActivity: Date.now(),
        });
        ws.roomCode = code;
        ws.peerId = 1;
        send(ws, { type: 'hosted', code, peer_id: 1, ice_servers: await iceServersForClient(!!msg.relay_tcp) });
        console.log(`room ${code} created`);
        break;
      }

      case 'join': {
        if (ws.roomCode) return;
        const code = String(msg.code || '').trim().toUpperCase();
        const target = rooms.get(code);
        if (!target) {
          send(ws, { type: 'error', reason: 'No game with that code' });
          return;
        }
        if (target.peers.size >= MAX_PLAYERS) {
          send(ws, { type: 'error', reason: 'Game is full' });
          return;
        }
        const peerId = target.nextPeerId++;
        target.peers.set(peerId, ws);
        target.lastActivity = Date.now();
        ws.roomCode = code;
        ws.peerId = peerId;
        send(ws, { type: 'joined', peer_id: peerId, host_id: 1, ice_servers: await iceServersForClient(!!msg.relay_tcp) });
        send(target.peers.get(1), { type: 'peer_joined', peer_id: peerId });
        console.log(`peer ${peerId} joined room ${code}`);
        break;
      }

      case 'offer':
      case 'answer':
      case 'candidate': {
        if (!room) return;
        const to = room.peers.get(Number(msg.to));
        if (to) send(to, { type: msg.type, from: ws.peerId, data: msg.data });
        break;
      }

      case 'leave':
        ws.close();
        break;
    }
  });

  ws.on('close', () => {
    if (!ws.roomCode) return;
    const room = rooms.get(ws.roomCode);
    if (!room) return;
    room.peers.delete(ws.peerId);
    if (ws.peerId === 1 || room.peers.size === 0) {
      // Host gone (or room empty): tear the room down. Peers that already
      // hold direct connections keep playing; signaling is only for setup.
      for (const peer of room.peers.values()) {
        send(peer, { type: 'peer_left', peer_id: 1 });
        peer.close();
      }
      rooms.delete(ws.roomCode);
      console.log(`room ${ws.roomCode} closed`);
    } else {
      send(room.peers.get(1), { type: 'peer_left', peer_id: ws.peerId });
    }
  });
});

// Reap rooms idle past the timeout (host crashed without closing, etc.).
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (now - room.lastActivity > ROOM_IDLE_TIMEOUT_MS) {
      for (const peer of room.peers.values()) peer.close();
      rooms.delete(code);
      console.log(`room ${code} expired`);
    }
  }
}, 60 * 1000);
