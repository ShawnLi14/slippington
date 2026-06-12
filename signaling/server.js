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

// Handed to clients so TURN can be added later without touching the game.
const ICE_SERVERS = [
  { urls: ['stun:stun.l.google.com:19302'] },
  { urls: ['stun:stun1.l.google.com:19302'] },
];

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

  ws.on('message', (raw) => {
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
        send(ws, { type: 'hosted', code, peer_id: 1, ice_servers: ICE_SERVERS });
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
        send(ws, { type: 'joined', peer_id: peerId, host_id: 1, ice_servers: ICE_SERVERS });
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
