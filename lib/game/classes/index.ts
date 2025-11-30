import { PlayerClass, PlayerClassId } from './types';
import { SpeedsterClass } from './SpeedsterClass';
import { TankClass } from './TankClass';
import { TricksterClass } from './TricksterClass';

export * from './types';
export * from './BaseClass';

/**
 * Registry of all available player classes
 */
export const CLASS_REGISTRY: Record<PlayerClassId, PlayerClass> = {
  speedster: SpeedsterClass,
  tank: TankClass,
  trickster: TricksterClass,
};

export function getClass(id: PlayerClassId): PlayerClass {
  const playerClass = CLASS_REGISTRY[id];
  if (!playerClass) {
    throw new Error(`Unknown class: ${id}`);
  }
  return playerClass;
}

export function getAllClasses(): PlayerClass[] {
  return Object.values(CLASS_REGISTRY);
}

