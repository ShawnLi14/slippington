/**
 * Sprite sheet definitions for asset loading
 */

export interface SpriteSheetConfig {
  key: string;
  path: string;
  frameWidth: number;
  frameHeight: number;
}

/**
 * All sprite sheets used in the game
 * These will be loaded in the LoadingScene
 */
export const SPRITE_SHEETS: SpriteSheetConfig[] = [
  {
    key: 'slipper',
    path: '/assets/sprites/slipper.png',
    frameWidth: 32,
    frameHeight: 32,
  },
  {
    key: 'default',
    path: '/assets/sprites/default.png',
    frameWidth: 32,
    frameHeight: 32,
  },
];

/**
 * Static images (non-animated)
 */
export interface ImageConfig {
  key: string;
  path: string;
}

export const IMAGES: ImageConfig[] = [
  { key: 'background_arena', path: '/assets/backgrounds/arena.png' },
  { key: 'platform_solid', path: '/assets/platforms/solid.png' },
  { key: 'platform_passthrough', path: '/assets/platforms/passthrough.png' },
];

/**
 * Ability icons
 */
export const ABILITY_ICONS: ImageConfig[] = [
  { key: 'ability_blink', path: '/assets/icons/blink.png' },
];
