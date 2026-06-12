"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const ws_1 = require("ws");
const Game_1 = require("./Game");
const PORT = 8080;
const wss = new ws_1.WebSocketServer({ port: PORT });
const game = new Game_1.Game();
console.log(`Server started on port ${PORT}`);
wss.on('connection', (ws) => {
    console.log('New client connected');
    const playerId = game.addPlayer(ws);
    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data.toString());
            game.handleInput(playerId, message);
        }
        catch (e) {
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
