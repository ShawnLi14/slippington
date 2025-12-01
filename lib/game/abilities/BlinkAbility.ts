import { Ability, AbilityContext } from './types';
import { GAME_CONFIG } from '@/lib/game/constants';

const BLINK_DISTANCE = 150;

/**
 * Linear interpolation helper (to avoid importing Phaser)
 */
function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/**
 * Clamp helper
 */
function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Blink - Short-range teleport in facing direction
 * 
 * Note: This file avoids importing Phaser directly to prevent SSR issues.
 * The scene is typed as `unknown` and cast at runtime.
 */
export const BlinkAbility: Ability = {
  id: 'blink',
  name: 'Blink',
  description: 'Instantly teleport a short distance in your facing direction.',
  icon: 'ability_blink',
  
  cooldown: 10000, // 10 seconds
  
  config: {
    distance: BLINK_DISTANCE,
  },
  
  execute: (context: AbilityContext) => {
    const { scene, playerX, playerY, facingRight, setPlayerPosition } = context;
    
    // Calculate blink destination
    const direction = facingRight ? 1 : -1;
    let targetX = playerX + (BLINK_DISTANCE * direction);
    
    // Clamp to world bounds
    targetX = clamp(
      targetX, 
      GAME_CONFIG.PLAYER_SIZE / 2, 
      GAME_CONFIG.MAP_WIDTH - GAME_CONFIG.PLAYER_SIZE / 2
    );

    // Teleport player
    setPlayerPosition(targetX, playerY);

    // Visual effects - cast scene to access Phaser methods
    // This code only runs client-side where Phaser is available
    const phaserScene = scene as {
      add: {
        circle: (x: number, y: number, r: number, color: number, alpha: number) => {
          setAlpha: (a: number) => void;
          destroy: () => void;
        };
      };
      tweens: {
        add: (config: unknown) => void;
      };
    };

    // Trail particles
    const numParticles = 8;
    for (let i = 0; i < numParticles; i++) {
      const t = i / numParticles;
      const x = lerp(playerX, targetX, t);
      const y = lerp(playerY, playerY, t);
      
      const particle = phaserScene.add.circle(x, y, 6, 0x4ecdc4, 0.8);
      
      phaserScene.tweens.add({
        targets: particle,
        alpha: 0,
        scale: 0.2,
        duration: 300,
        delay: i * 20,
        onComplete: () => particle.destroy(),
      });
    }

    // Flash at destination
    const flash = phaserScene.add.circle(targetX, playerY, 20, 0x4ecdc4, 0.6);
    phaserScene.tweens.add({
      targets: flash,
      alpha: 0,
      scale: 2,
      duration: 200,
      onComplete: () => flash.destroy(),
    });

    return { success: true, newX: targetX, newY: playerY };
  },
};
