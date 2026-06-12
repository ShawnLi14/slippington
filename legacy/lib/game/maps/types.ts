/**
 * Platform definition for map generation
 */
export interface Platform {
  x: number;
  y: number;
  width: number;
  height: number;
  type: PlatformType;
}

export type PlatformType = 'solid' | 'passthrough' | 'moving' | 'crumbling';

/**
 * Spawn point for players
 */
export interface SpawnPoint {
  x: number;
  y: number;
}

/**
 * Complete map data - can be serialized and shared
 */
export interface MapData {
  seed: string;
  width: number;
  height: number;
  platforms: Platform[];
  spawnPoints: SpawnPoint[];
  background?: string;
}

/**
 * Map generation options
 */
export interface MapGeneratorOptions {
  width: number;
  height: number;
  platformCount: number;
  minPlatformWidth: number;
  maxPlatformWidth: number;
  verticalSpacing: number;
}

