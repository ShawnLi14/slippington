import { SlipperClass } from './SlipperClass';
import { PlayerClass, PlayerClassId } from './types';

export * from './types';
export * from './BaseClass';
export * from './SlipperClass';

const classes: Record<PlayerClassId, PlayerClass> = {
  slipper: SlipperClass,
};

export function getClass(id: PlayerClassId | string): PlayerClass {
  return classes[id as PlayerClassId] || classes.slipper;
}

export function getAllClasses(): PlayerClass[] {
  return Object.values(classes);
}
