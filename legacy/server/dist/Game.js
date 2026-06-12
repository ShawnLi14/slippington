"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Game = void 0;
const ws_1 = require("ws");
const uuid_1 = require("uuid");
class Game {
    constructor() {
        this.players = new Map();
        this.sockets = new Map();
        this.inputs = new Map();
        // Physics constants
        this.GRAVITY = 0.5;
        this.JUMP_FORCE = -12;
        this.MOVE_SPEED = 5;
        this.FRICTION = 0.8;
        // Map boundaries (simple box for now)
        this.MAP_WIDTH = 800;
        this.MAP_HEIGHT = 600;
    }
    addPlayer(ws) {
        const id = (0, uuid_1.v4)();
        this.sockets.set(id, ws);
        // Initialize player state
        this.players.set(id, {
            id,
            x: Math.random() * (this.MAP_WIDTH - 50) + 25,
            y: 100,
            vx: 0,
            vy: 0,
            isIt: this.players.size === 0, // First player is "It"
            color: '#' + Math.floor(Math.random() * 16777215).toString(16),
            facingRight: true
        });
        // Send initial state immediately
        this.broadcastState();
        return id;
    }
    removePlayer(id) {
        this.players.delete(id);
        this.sockets.delete(id);
        this.inputs.delete(id);
    }
    handleInput(id, message) {
        if (message.type === 'input') {
            this.inputs.set(id, message.payload);
        }
    }
    update() {
        this.players.forEach((player, id) => {
            const input = this.inputs.get(id);
            // Apply physics based on input
            if (input) {
                if (input.left) {
                    player.vx -= 1;
                    player.facingRight = false;
                }
                if (input.right) {
                    player.vx += 1;
                    player.facingRight = true;
                }
                if (input.jump && player.y >= this.MAP_HEIGHT - 40) { // Simple ground check
                    player.vy = this.JUMP_FORCE;
                }
            }
            // Apply gravity
            player.vy += this.GRAVITY;
            // Apply friction
            player.vx *= this.FRICTION;
            // Update positions
            player.x += player.vx;
            player.y += player.vy;
            // Bounds checking (Ground)
            if (player.y > this.MAP_HEIGHT - 40) {
                player.y = this.MAP_HEIGHT - 40;
                player.vy = 0;
            }
            // Walls
            if (player.x < 0) {
                player.x = 0;
                player.vx = 0;
            }
            if (player.x > this.MAP_WIDTH) {
                player.x = this.MAP_WIDTH;
                player.vx = 0;
            }
        });
        this.broadcastState();
    }
    broadcastState() {
        const state = {
            players: Object.fromEntries(this.players),
            timestamp: Date.now()
        };
        const data = JSON.stringify({ type: 'state', payload: state });
        this.sockets.forEach(ws => {
            if (ws.readyState === ws_1.WebSocket.OPEN) {
                ws.send(data);
            }
        });
    }
}
exports.Game = Game;
