import { defineClass } from './BaseClass';
import { DashAbility } from '../abilities/DashAbility';
import { SpeedBoostAbility } from '../abilities/SpeedBoostAbility';

export const SpeedsterClass = defineClass({
  id: 'speedster',
  name: 'Speedster',
  description: 'Fast and agile. Excels at chasing and escaping.',
  spriteSheet: 'speedster',
  
  stats: {
    speed: 1.3,
    jumpForce: 1.1,
    mass: 0.8,
  },

  abilities: {
    primary: DashAbility,
    secondary: SpeedBoostAbility,
  },
});

