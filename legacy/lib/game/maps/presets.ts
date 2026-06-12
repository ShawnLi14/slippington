import { MapData } from './types';
import { GAME_CONFIG } from '../constants';

/**
 * Hand-crafted map presets for variety
 */

export const PRESET_ARENA: MapData = {
  seed: 'preset_arena',
  width: GAME_CONFIG.MAP_WIDTH,
  height: GAME_CONFIG.MAP_HEIGHT,
  platforms: [
    // Ground
    { x: 0, y: 580, width: 800, height: 20, type: 'solid' },
    // Lower platforms
    { x: 50, y: 480, width: 150, height: 16, type: 'solid' },
    { x: 600, y: 480, width: 150, height: 16, type: 'solid' },
    // Middle platforms
    { x: 300, y: 400, width: 200, height: 16, type: 'solid' },
    { x: 100, y: 320, width: 120, height: 16, type: 'passthrough' },
    { x: 580, y: 320, width: 120, height: 16, type: 'passthrough' },
    // Upper platforms
    { x: 250, y: 240, width: 300, height: 16, type: 'solid' },
    // Top platforms
    { x: 50, y: 160, width: 100, height: 16, type: 'solid' },
    { x: 650, y: 160, width: 100, height: 16, type: 'solid' },
  ],
  spawnPoints: [
    { x: 125, y: 450 },
    { x: 675, y: 450 },
    { x: 400, y: 370 },
    { x: 400, y: 210 },
  ],
};

export const PRESET_TOWERS: MapData = {
  seed: 'preset_towers',
  width: GAME_CONFIG.MAP_WIDTH,
  height: GAME_CONFIG.MAP_HEIGHT,
  platforms: [
    // Ground
    { x: 0, y: 580, width: 800, height: 20, type: 'solid' },
    // Left tower
    { x: 50, y: 480, width: 80, height: 16, type: 'solid' },
    { x: 50, y: 380, width: 80, height: 16, type: 'solid' },
    { x: 50, y: 280, width: 80, height: 16, type: 'solid' },
    { x: 50, y: 180, width: 80, height: 16, type: 'solid' },
    // Right tower
    { x: 670, y: 480, width: 80, height: 16, type: 'solid' },
    { x: 670, y: 380, width: 80, height: 16, type: 'solid' },
    { x: 670, y: 280, width: 80, height: 16, type: 'solid' },
    { x: 670, y: 180, width: 80, height: 16, type: 'solid' },
    // Bridges
    { x: 130, y: 330, width: 540, height: 16, type: 'passthrough' },
    { x: 200, y: 230, width: 400, height: 16, type: 'passthrough' },
  ],
  spawnPoints: [
    { x: 90, y: 550 },
    { x: 710, y: 550 },
    { x: 90, y: 150 },
    { x: 710, y: 150 },
  ],
};

export const MAP_PRESETS = {
  arena: PRESET_ARENA,
  towers: PRESET_TOWERS,
} as const;

export type MapPresetId = keyof typeof MAP_PRESETS;

