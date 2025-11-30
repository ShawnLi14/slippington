import { Ability } from './types';

export const DecoyAbility: Ability = {
  id: 'decoy',
  name: 'Decoy',
  description: 'Spawn a fake copy of yourself that runs in a direction.',
  icon: 'ability_decoy',
  cooldown: 6000,
  duration: 4000,

  execute: (context) => {
    console.log(`[Decoy] Player ${context.playerId} spawned decoy`);
  },

  onEnd: (context) => {
    console.log(`[Decoy] Player ${context.playerId} decoy disappeared`);
  },
};

