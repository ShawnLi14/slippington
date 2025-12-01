/**
 * Ability definition - describes what an ability does
 */
export interface Ability {
  id: string;
  name: string;
  description: string;
  icon: string;              // Asset key for UI
  
  cooldown: number;          // Cooldown in milliseconds
  duration?: number;         // Duration for timed effects (ms)
  
  // These will be called by AbilityManager
  // Scene reference allows spawning effects, playing sounds, etc.
  execute: (context: AbilityContext) => void;
  onEnd?: (context: AbilityContext) => void;
}

/**
 * Context passed to ability execution
 */
export interface AbilityContext {
  playerId: string;
  playerX: number;
  playerY: number;
  facingRight: boolean;
  // Scene and other references will be added when we implement
}

/**
 * Runtime state of an ability for a specific player
 */
export interface AbilityState {
  abilityId: string;
  lastUsed: number;          // Timestamp
  isActive: boolean;         // For duration-based abilities
  expiresAt?: number;        // When active effect ends
}

export type AbilitySlot = 'primary';

