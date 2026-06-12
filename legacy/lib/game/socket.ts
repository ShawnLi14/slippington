import { InputState } from '@/server/src/types'; // We'll need to share types properly later, for now we'll redefine or import
import { Player } from './types';

// Define types locally to avoid importing from outside src (Next.js restriction usually)
export interface ServerInputState {
    up: boolean;
    down: boolean;
    left: boolean;
    right: boolean;
    jump: boolean;
}

export type ServerMessage = 
    | { type: 'state'; payload: { players: Record<string, any>; timestamp: number } }
    | { type: 'welcome'; payload: { id: string } };

type StateHandler = (state: { players: Record<string, any>; timestamp: number }) => void;

export class GameSocket {
    private ws: WebSocket | null = null;
    private messageHandlers: Set<StateHandler> = new Set();
    public playerId: string | null = null;
    private connectPromise: Promise<string> | null = null;

    constructor(private url: string = process.env.NEXT_PUBLIC_GAME_SERVER_URL || 'ws://localhost:8080') {}

    connect(): Promise<string> {
        if (this.connectPromise) return this.connectPromise;

        this.connectPromise = new Promise((resolve, reject) => {
            this.ws = new WebSocket(this.url);

            this.ws.onopen = () => {
                console.log('Connected to game server');
            };

            this.ws.onmessage = (event) => {
                try {
                    const message = JSON.parse(event.data) as ServerMessage;
                    
                    if (message.type === 'welcome') {
                        this.playerId = message.payload.id;
                        console.log('Assigned player ID:', this.playerId);
                        resolve(this.playerId);
                    } else if (message.type === 'state') {
                        this.notifyStateHandlers(message.payload);
                    }
                } catch (e) {
                    console.error('Failed to parse server message:', e);
                }
            };

            this.ws.onerror = (error) => {
                console.error('WebSocket error:', error);
                reject(error);
            };
        });

        return this.connectPromise;
    }

    sendInput(input: ServerInputState) {
        if (this.ws?.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ type: 'input', payload: input }));
        }
    }

    onStateUpdate(handler: StateHandler) {
        this.messageHandlers.add(handler);
        return () => this.messageHandlers.delete(handler);
    }

    private notifyStateHandlers(state: any) {
        this.messageHandlers.forEach(handler => handler(state));
    }

    disconnect() {
        this.ws?.close();
        this.ws = null;
        this.connectPromise = null;
        this.playerId = null;
    }
}

export const gameSocket = new GameSocket();
