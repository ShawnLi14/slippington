import { MapData, Platform, SpawnPoint, MapGeneratorOptions } from './types';
import { GAME_CONFIG } from '../constants';

/**
 * Seeded random number generator for deterministic map generation
 */
class SeededRandom {
  private seed: number;

  constructor(seed: string) {
    // Convert string seed to number
    this.seed = this.hashString(seed);
  }

  private hashString(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash);
  }

  next(): number {
    this.seed = (this.seed * 1103515245 + 12345) & 0x7fffffff;
    return this.seed / 0x7fffffff;
  }

  nextInt(min: number, max: number): number {
    return Math.floor(this.next() * (max - min + 1)) + min;
  }

  nextFloat(min: number, max: number): number {
    return this.next() * (max - min) + min;
  }
}

const DEFAULT_OPTIONS: MapGeneratorOptions = {
  width: GAME_CONFIG.MAP_WIDTH,
  height: GAME_CONFIG.MAP_HEIGHT,
  platformCount: 8,
  minPlatformWidth: 80,
  maxPlatformWidth: 200,
  verticalSpacing: 80,
};

/**
 * Generates a deterministic map from a seed
 * Same seed = same map on all clients
 */
export class MapGenerator {
  private rng: SeededRandom;
  private options: MapGeneratorOptions;

  constructor(seed: string, options: Partial<MapGeneratorOptions> = {}) {
    this.rng = new SeededRandom(seed);
    this.options = { ...DEFAULT_OPTIONS, ...options };
  }

  generate(): MapData {
    const platforms: Platform[] = [];
    const spawnPoints: SpawnPoint[] = [];

    // Always add ground platform
    platforms.push({
      x: 0,
      y: this.options.height - 20,
      width: this.options.width,
      height: 20,
      type: 'solid',
    });

    // Generate floating platforms
    const layers = Math.floor((this.options.height - 100) / this.options.verticalSpacing);
    
    for (let layer = 0; layer < layers; layer++) {
      const y = this.options.height - 100 - (layer * this.options.verticalSpacing);
      const platformsInLayer = this.rng.nextInt(1, 3);

      for (let i = 0; i < platformsInLayer; i++) {
        const width = this.rng.nextInt(
          this.options.minPlatformWidth,
          this.options.maxPlatformWidth
        );
        const x = this.rng.nextInt(20, this.options.width - width - 20);

        // Check for overlap with existing platforms in this layer
        const overlaps = platforms.some(p => 
          p.y === y && 
          x < p.x + p.width + 30 && 
          x + width + 30 > p.x
        );

        if (!overlaps) {
          platforms.push({
            x,
            y,
            width,
            height: 16,
            type: this.rng.next() > 0.8 ? 'passthrough' : 'solid',
          });
        }
      }
    }

    // Generate spawn points on platforms
    const platformsForSpawns = platforms.filter(p => p.width >= 60);
    for (let i = 0; i < Math.min(4, platformsForSpawns.length); i++) {
      const platform = platformsForSpawns[i];
      spawnPoints.push({
        x: platform.x + platform.width / 2,
        y: platform.y - 30,
      });
    }

    // Ensure at least 2 spawn points
    while (spawnPoints.length < 2) {
      spawnPoints.push({
        x: this.rng.nextInt(100, this.options.width - 100),
        y: this.options.height - 50,
      });
    }

    return {
      seed: this.rng.toString(),
      width: this.options.width,
      height: this.options.height,
      platforms,
      spawnPoints,
    };
  }

  /**
   * Generate a random seed string
   */
  static generateSeed(): string {
    return `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}

