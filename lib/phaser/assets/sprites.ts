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
    key: 'speedster',
    path: '/assets/sprites/speedster.png',
    frameWidth: 48,
    frameHeight: 48,
  },
  {
    key: 'tank',
    path: '/assets/sprites/tank.png',
    frameWidth: 48,
    frameHeight: 48,
  },
  {
    key: 'trickster',
    path: '/assets/sprites/trickster.png',
    frameWidth: 48,
    frameHeight: 48,
  },
  {
    key: 'default',
    path: '/assets/sprites/default.png',
    frameWidth: 48,
    frameHeight: 48,
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
  { key: 'ability_dash', path: '/assets/icons/dash.png' },
  { key: 'ability_speed', path: '/assets/icons/speed.png' },
  { key: 'ability_shield', path: '/assets/icons/shield.png' },
  { key: 'ability_pound', path: '/assets/icons/pound.png' },
  { key: 'ability_decoy', path: '/assets/icons/decoy.png' },
  { key: 'ability_teleport', path: '/assets/icons/teleport.png' },
];

