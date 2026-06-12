import { WebSocketServer, WebSocket } from 'ws';
import { Game } from './Game';
import { ClientMessage } from './types';

const PORT = 8080;
const wss = new WebSocketServer({ port: PORT });
const game = new Game();

console.log(`Server started on port ${PORT}`);

wss.on('connection', (ws: WebSocket) => {
    console.log('New client connected');
    const playerId = game.addPlayer(ws);

    ws.on('message', (data: Buffer) => {
        try {
            const message: ClientMessage = JSON.parse(data.toString());
            game.handleInput(playerId, message);
        } catch (e) {
            console.error('Failed to parse message:', e);
        }
    });

    ws.on('close', () => {
        console.log(`Client ${playerId} disconnected`);
        game.removePlayer(playerId);
    });
});

// Start the game loop
const TICK_RATE = 60;
setInterval(() => {
    game.update();
}, 1000 / TICK_RATE);

