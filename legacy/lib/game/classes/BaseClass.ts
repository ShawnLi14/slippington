import { PlayerClass } from './types';

/**
 * Default stats that all classes start with
 * Individual classes override these values
 */
export const BASE_STATS = {
  speed: 1.0,
  jumpForce: 1.0,
  mass: 1.0,
} as const;

/**
 * Creates a player class with defaults applied
 */
export function defineClass(partial: Partial<PlayerClass> & Pick<PlayerClass, 'id' | 'name' | 'abilities'>): PlayerClass {
  return {
    description: '',
    spriteSheet: 'default',
    stats: { ...BASE_STATS },
    ...partial,
  };
}

