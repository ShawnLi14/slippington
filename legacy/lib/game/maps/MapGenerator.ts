import { MapData, Platform, SpawnPoint, MapGeneratorOptions } from './types';
import { GAME_CONFIG } from '../constants';

/**
 * Seeded random number generator for deterministic map generation
 */
class SeededRandom {
  private seed: number;
  private initialSeed: string;

  constructor(seed: string) {
    this.initialSeed = seed;
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

  getSeed(): string {
    return this.initialSeed;
  }
}

/**
 * Calculate max jump height from physics
 * Using kinematic equation: v² = v₀² + 2as
 * At peak: v = 0, so height = v₀² / (2 * g)
 */
function calculateMaxJumpHeight(): number {
  const jumpVelocity = Math.abs(GAME_CONFIG.JUMP_FORCE);
  const gravity = GAME_CONFIG.GRAVITY;
  return (jumpVelocity * jumpVelocity) / (2 * gravity);
}

const MAX_JUMP_HEIGHT = calculateMaxJumpHeight();

// Use 80% of max jump height for comfortable jumps
const SAFE_JUMP_HEIGHT = MAX_JUMP_HEIGHT * 0.8;

const DEFAULT_OPTIONS: MapGeneratorOptions = {
  width: GAME_CONFIG.MAP_WIDTH,
  height: GAME_CONFIG.MAP_HEIGHT,
  platformCount: 12,
  minPlatformWidth: 120,  // Minimum platform length
  maxPlatformWidth: 280,
  verticalSpacing: Math.floor(SAFE_JUMP_HEIGHT), // Based on jump height
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

    // Track platforms by layer for reachability checks
    const platformsByLayer: Platform[][] = [[platforms[0]]];

    // Generate floating platforms layer by layer
    const numLayers = Math.floor((this.options.height - 150) / this.options.verticalSpacing);
    
    for (let layer = 1; layer <= numLayers; layer++) {
      const layerPlatforms: Platform[] = [];
      const y = this.options.height - 20 - (layer * this.options.verticalSpacing);
      
      // Skip if too close to top
      if (y < 80) continue;

      const platformsInLayer = this.rng.nextInt(2, 4);
      const previousLayer = platformsByLayer[layer - 1] || platformsByLayer[0];

      for (let i = 0; i < platformsInLayer; i++) {
        const width = this.rng.nextInt(
          this.options.minPlatformWidth,
          this.options.maxPlatformWidth
        );
        
        // Try to place platform reachable from a platform below
        const basePlatform = previousLayer[this.rng.nextInt(0, previousLayer.length - 1)];
        
        // Calculate horizontal range player can reach while jumping
        // Rough estimate: player can move horizontally during jump time
        const jumpTime = 2 * Math.abs(GAME_CONFIG.JUMP_FORCE) / GAME_CONFIG.GRAVITY;
        const maxHorizontalDistance = GAME_CONFIG.PLAYER_SPEED * jumpTime;
        
        // Position new platform within reachable range of base platform
        const minX = Math.max(20, basePlatform.x - maxHorizontalDistance);
        const maxX = Math.min(
          this.options.width - width - 20,
          basePlatform.x + basePlatform.width + maxHorizontalDistance - width
        );
        
        if (maxX < minX) continue; // Can't place platform
        
        const x = this.rng.nextInt(Math.floor(minX), Math.floor(maxX));

        // Check for overlap with existing platforms in this layer
        const overlaps = layerPlatforms.some(p => 
          x < p.x + p.width + 50 && 
          x + width + 50 > p.x
        );

        if (!overlaps) {
          const platform: Platform = {
            x,
            y,
            width,
            height: 16,
            type: 'solid', // All platforms are solid now
          };
          platforms.push(platform);
          layerPlatforms.push(platform);
        }
      }

      // Ensure at least one platform per layer for connectivity
      if (layerPlatforms.length === 0 && previousLayer.length > 0) {
        const basePlatform = previousLayer[0];
        const width = this.options.minPlatformWidth;
        const x = Math.max(20, Math.min(
          this.options.width - width - 20,
          basePlatform.x + basePlatform.width / 2 - width / 2
        ));
        
        const platform: Platform = {
          x,
          y,
          width,
          height: 16,
          type: 'solid',
        };
        platforms.push(platform);
        layerPlatforms.push(platform);
      }

      platformsByLayer.push(layerPlatforms);
    }

    // Generate spawn points on platforms (prefer ground and lower platforms)
    const sortedPlatforms = [...platforms].sort((a, b) => b.y - a.y);
    const platformsForSpawns = sortedPlatforms.filter(p => p.width >= this.options.minPlatformWidth);
    
    for (let i = 0; i < Math.min(4, platformsForSpawns.length); i++) {
      const platform = platformsForSpawns[i];
      spawnPoints.push({
        x: platform.x + platform.width / 2,
        y: platform.y - GAME_CONFIG.PLAYER_SIZE,
      });
    }

    // Ensure at least 2 spawn points on ground
    while (spawnPoints.length < 2) {
      spawnPoints.push({
        x: this.rng.nextInt(100, this.options.width - 100),
        y: this.options.height - 20 - GAME_CONFIG.PLAYER_SIZE,
      });
    }

    return {
      seed: this.rng.getSeed(),
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
