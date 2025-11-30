import { Ability } from './types';

export const SpeedBoostAbility: Ability = {
  id: 'speed_boost',
  name: 'Speed Boost',
  description: 'Temporarily increase movement speed.',
  icon: 'ability_speed',
  cooldown: 8000,
  duration: 3000,

  execute: (context) => {
    console.log(`[SpeedBoost] Player ${context.playerId} speed increased`);
  },

  onEnd: (context) => {
    console.log(`[SpeedBoost] Player ${context.playerId} speed returned to normal`);
  },
};

