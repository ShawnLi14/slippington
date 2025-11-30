import { Ability } from './types';

export const GroundPoundAbility: Ability = {
  id: 'ground_pound',
  name: 'Ground Pound',
  description: 'Slam down and stun nearby players on impact.',
  icon: 'ability_pound',
  cooldown: 10000,

  execute: (context) => {
    console.log(`[GroundPound] Player ${context.playerId} slamming down`);
  },
};

