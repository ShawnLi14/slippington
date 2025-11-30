import { defineClass } from './BaseClass';
import { ShieldAbility } from '../abilities/ShieldAbility';
import { GroundPoundAbility } from '../abilities/GroundPoundAbility';

export const TankClass = defineClass({
  id: 'tank',
  name: 'Tank',
  description: 'Slow but sturdy. Hard to knock around.',
  spriteSheet: 'tank',
  
  stats: {
    speed: 0.8,
    jumpForce: 0.9,
    mass: 1.5,
  },

  abilities: {
    primary: ShieldAbility,
    secondary: GroundPoundAbility,
  },
});

