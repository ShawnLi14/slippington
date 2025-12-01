import { Ability } from './types';

/**
 * Blink - Short-range teleport in facing direction
 */
export const BlinkAbility: Ability = {
  id: 'blink',
  name: 'Blink',
  description: 'Instantly teleport a short distance in your facing direction.',
  icon: 'ability_blink',
  
  cooldown: 10000, // 10 seconds
  
  execute: (context) => {
    // The actual teleport logic will be handled by the game scene
    // This just defines the ability properties
    console.log('Blink executed!', context);
  },
};
