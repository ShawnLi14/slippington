import { PlayerClassId } from './classes/types';

/**
 * Player data as stored in state
 */
export interface Player {
  id: string;
  game_id: string | null;
  user_id: string;
  x: number;
  y: number;
  velocity_y: number;
  is_it: boolean;
  color: string;
  class_id: PlayerClassId;
  facing_right: boolean;
}

/**
 * Global game state
 */
export interface GameState {
  // Connection state
  gameId: string | null;
  localPlayerId: string | null;
  selectedClass: string | null;
  
  // Game state
  players: Record<string, Player>;
  status: 'loading' | 'lobby' | 'waiting' | 'playing' | 'finished';
  timerEnd: string | null;
  mapSeed: string | null;
}

/**
 * Game settings (stored in games table)
 */
export interface GameSettings {
  duration: number;           // Game duration in seconds
  mapPreset?: string;         // Use preset map instead of random
  maxPlayers: number;
}

export const DEFAULT_GAME_SETTINGS: GameSettings = {
  duration: 60,
  maxPlayers: 8,
};
