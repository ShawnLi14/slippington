import { defineClass } from './BaseClass';
import { DecoyAbility } from '../abilities/DecoyAbility';
import { TeleportAbility } from '../abilities/TeleportAbility';

export const TricksterClass = defineClass({
  id: 'trickster',
  name: 'Trickster',
  description: 'Deceptive and unpredictable. Masters of misdirection.',
  spriteSheet: 'trickster',
  
  stats: {
    speed: 1.0,
    jumpForce: 1.0,
    mass: 1.0,
  },

  abilities: {
    primary: DecoyAbility,
    secondary: TeleportAbility,
  },
});

