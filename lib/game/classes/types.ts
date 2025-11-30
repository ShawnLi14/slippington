import { Ability } from '../abilities/types';

/**
 * Player class definition - data-driven class system
 */
export interface PlayerClass {
  id: string;
  name: string;
  description: string;
  spriteSheet: string;
  
  stats: {
    speed: number;        // Movement speed multiplier
    jumpForce: number;    // Jump strength
    mass: number;         // Affects knockback
  };

  abilities: {
    primary: Ability;     // Q key
    secondary: Ability;   // E key
  };
}

export type PlayerClassId = 'speedster' | 'tank' | 'trickster';

