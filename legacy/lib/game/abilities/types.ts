/**
 * Context passed to ability execution
 * Uses generic types to avoid importing Phaser in shared code
 */
export interface AbilityContext {
  scene: unknown;  // Phaser.Scene - typed as unknown to avoid SSR issues
  playerId: string;
  playerX: number;
  playerY: number;
  facingRight: boolean;
  setPlayerPosition: (x: number, y: number) => void;
}

/**
 * Result of ability execution
 */
export interface AbilityResult {
  success: boolean;
  newX?: number;
  newY?: number;
}

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
  
  // Constants specific to this ability
  config?: Record<string, number>;
  
  // Execute the ability - returns result
  execute: (context: AbilityContext) => AbilityResult;
  
  // Optional: called when duration-based effect ends
  onEnd?: (context: AbilityContext) => void;
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
