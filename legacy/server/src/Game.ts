import { WebSocket } from 'ws';
import { v4 as uuidv4 } from 'uuid';
import { PlayerState, GameState, ClientMessage, InputState } from './types';

export class Game {
    private players: Map<string, PlayerState> = new Map();
    private sockets: Map<string, WebSocket> = new Map();
    private inputs: Map<string, InputState> = new Map();

    // Physics constants
    private readonly GRAVITY = 0.5;
    private readonly JUMP_FORCE = -12;
    private readonly MOVE_SPEED = 5;
    private readonly FRICTION = 0.8;
    
    // Map boundaries (simple box for now)
    private readonly MAP_WIDTH = 800;
    private readonly MAP_HEIGHT = 600;

    constructor() {}

    addPlayer(ws: WebSocket): string {
        const id = uuidv4();
        this.sockets.set(id, ws);
        
        // Initialize player state
        this.players.set(id, {
            id,
            x: Math.random() * (this.MAP_WIDTH - 50) + 25,
            y: 100,
            vx: 0,
            vy: 0,
            isIt: this.players.size === 0, // First player is "It"
            color: '#'+Math.floor(Math.random()*16777215).toString(16),
            facingRight: true
        });

        // Send welcome packet with ID
        ws.send(JSON.stringify({ type: 'welcome', payload: { id } }));

        // Send initial state immediately
        this.broadcastState();
        
        return id;
    }

    removePlayer(id: string) {
        this.players.delete(id);
        this.sockets.delete(id);
        this.inputs.delete(id);
    }
    // ... (rest of the class is the same)

    handleInput(id: string, message: ClientMessage) {
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

    private broadcastState() {
        const state: GameState = {
            players: Object.fromEntries(this.players),
            timestamp: Date.now()
        };

        const data = JSON.stringify({ type: 'state', payload: state });
        this.sockets.forEach(ws => {
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(data);
            }
        });
    }
}
