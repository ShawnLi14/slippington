import { defineClass } from './BaseClass';
import { BlinkAbility } from '../abilities/BlinkAbility';

export const SlipperClass = defineClass({
  id: 'slipper',
  name: 'Slipper',
  description: 'Slippery and elusive. Hard to catch.',
  spriteSheet: 'slipper',
  
  stats: {
    speed: 1.3,
    jumpForce: 1.1,
    mass: 0.8,
  },

  abilities: {
    primary: BlinkAbility,
  },
});

