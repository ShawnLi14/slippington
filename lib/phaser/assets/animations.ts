import { CharacterAnimations, AnimationState } from '../systems/AnimationSystem';

/**
 * Default animation frame layout
 * Assumes sprite sheet is organized in rows:
 * Row 0: Idle (frames 0-3)
 * Row 1: Run (frames 4-9)
 * Row 2: Jump (frames 10-12)
 * Row 3: Fall (frames 13-15)
 * Row 4: Land (frames 16-17)
 * Row 5: Abilities (frames 18-23)
 */

const DEFAULT_ANIMATIONS: Record<AnimationState, { start: number; end: number; frameRate: number; repeat: number }> = {
  idle: { start: 0, end: 3, frameRate: 8, repeat: -1 },
  run: { start: 4, end: 9, frameRate: 12, repeat: -1 },
  jump: { start: 10, end: 12, frameRate: 10, repeat: 0 },
  fall: { start: 13, end: 15, frameRate: 8, repeat: -1 },
  land: { start: 16, end: 17, frameRate: 12, repeat: 0 },
  ability_primary: { start: 18, end: 20, frameRate: 15, repeat: 0 },
  ability_secondary: { start: 21, end: 23, frameRate: 15, repeat: 0 },
};

function createAnimationConfig(state: AnimationState, key: string) {
  const config = DEFAULT_ANIMATIONS[state];
  return {
    key: `${key}_${state}`,
    frames: { start: config.start, end: config.end },
    frameRate: config.frameRate,
    repeat: config.repeat,
  };
}

/**
 * Animation configurations for each character class
 */
export const CHARACTER_ANIMATIONS: Record<string, CharacterAnimations> = {
  speedster: {
    spriteSheet: 'speedster',
    frameWidth: 48,
    frameHeight: 48,
    animations: {
      idle: createAnimationConfig('idle', 'speedster'),
      run: createAnimationConfig('run', 'speedster'),
      jump: createAnimationConfig('jump', 'speedster'),
      fall: createAnimationConfig('fall', 'speedster'),
      land: createAnimationConfig('land', 'speedster'),
      ability_primary: createAnimationConfig('ability_primary', 'speedster'),
      ability_secondary: createAnimationConfig('ability_secondary', 'speedster'),
    },
  },

  tank: {
    spriteSheet: 'tank',
    frameWidth: 48,
    frameHeight: 48,
    animations: {
      idle: createAnimationConfig('idle', 'tank'),
      run: createAnimationConfig('run', 'tank'),
      jump: createAnimationConfig('jump', 'tank'),
      fall: createAnimationConfig('fall', 'tank'),
      land: createAnimationConfig('land', 'tank'),
      ability_primary: createAnimationConfig('ability_primary', 'tank'),
      ability_secondary: createAnimationConfig('ability_secondary', 'tank'),
    },
  },

  trickster: {
    spriteSheet: 'trickster',
    frameWidth: 48,
    frameHeight: 48,
    animations: {
      idle: createAnimationConfig('idle', 'trickster'),
      run: createAnimationConfig('run', 'trickster'),
      jump: createAnimationConfig('jump', 'trickster'),
      fall: createAnimationConfig('fall', 'trickster'),
      land: createAnimationConfig('land', 'trickster'),
      ability_primary: createAnimationConfig('ability_primary', 'trickster'),
      ability_secondary: createAnimationConfig('ability_secondary', 'trickster'),
    },
  },

  default: {
    spriteSheet: 'default',
    frameWidth: 48,
    frameHeight: 48,
    animations: {
      idle: createAnimationConfig('idle', 'default'),
      run: createAnimationConfig('run', 'default'),
      jump: createAnimationConfig('jump', 'default'),
      fall: createAnimationConfig('fall', 'default'),
      land: createAnimationConfig('land', 'default'),
      ability_primary: createAnimationConfig('ability_primary', 'default'),
      ability_secondary: createAnimationConfig('ability_secondary', 'default'),
    },
  },
};

export function getCharacterAnimations(classId: string): CharacterAnimations {
  return CHARACTER_ANIMATIONS[classId] ?? CHARACTER_ANIMATIONS.default;
}

