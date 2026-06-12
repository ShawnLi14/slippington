export interface PlayerState {
    id: string;
    x: number;
    y: number;
    vx: number;
    vy: number;
    isIt: boolean;
    color: string;
    facingRight: boolean;
}

export interface InputState {
    up: boolean;
    down: boolean;
    left: boolean;
    right: boolean;
    jump: boolean;
}

export type ClientMessage = 
    | { type: 'input'; payload: InputState }
    | { type: 'join'; payload: { color: string } };

export type ServerMessage = 
    | { type: 'state'; payload: GameState }
    | { type: 'welcome'; payload: { id: string } };

export interface GameState {
    players: Record<string, PlayerState>;
    timestamp: number;
}

