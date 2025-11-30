import { Ability } from './types';

export const ShieldAbility: Ability = {
  id: 'shield',
  name: 'Shield',
  description: 'Become immune to being tagged for a short duration.',
  icon: 'ability_shield',
  cooldown: 12000,
  duration: 2000,

  execute: (context) => {
    console.log(`[Shield] Player ${context.playerId} shield activated`);
  },

  onEnd: (context) => {
    console.log(`[Shield] Player ${context.playerId} shield expired`);
  },
};

