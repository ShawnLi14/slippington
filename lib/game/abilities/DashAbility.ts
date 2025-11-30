import { Ability } from './types';

export const DashAbility: Ability = {
  id: 'dash',
  name: 'Dash',
  description: 'Quickly dash in the direction you\'re facing.',
  icon: 'ability_dash',
  cooldown: 3000,
  duration: 200,

  execute: (context) => {
    // Will apply velocity boost in facing direction
    console.log(`[Dash] Player ${context.playerId} dashing ${context.facingRight ? 'right' : 'left'}`);
  },

  onEnd: (context) => {
    console.log(`[Dash] Player ${context.playerId} dash ended`);
  },
};

