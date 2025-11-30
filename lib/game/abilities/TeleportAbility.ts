import { Ability } from './types';

export const TeleportAbility: Ability = {
  id: 'teleport',
  name: 'Teleport',
  description: 'Instantly teleport a short distance in the direction you\'re facing.',
  icon: 'ability_teleport',
  cooldown: 8000,

  execute: (context) => {
    console.log(`[Teleport] Player ${context.playerId} teleporting`);
  },
};

