import * as Phaser from 'phaser';
import { Platform } from '@/lib/game/maps/types';

/**
 * Manages collision detection and physics interactions
 */
export class CollisionSystem {
  private scene: Phaser.Scene;
  private platformGroup: Phaser.Physics.Arcade.StaticGroup;

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
    this.platformGroup = scene.physics.add.staticGroup();
  }

  /**
   * Create platform physics bodies from map data
   */
  createPlatforms(platforms: Platform[]): void {
    for (const platform of platforms) {
      const rect = this.scene.add.rectangle(
        platform.x + platform.width / 2,
        platform.y + platform.height / 2,
        platform.width,
        platform.height,
        0x5a5a7a
      );

      this.platformGroup.add(rect);
    }
  }

  /**
   * Set up collision between a player and platforms
   */
  addPlayerCollision(player: Phaser.Physics.Arcade.Sprite): void {
    this.scene.physics.add.collider(player, this.platformGroup);
  }

  /**
   * Set up collision between two players (for tagging)
   */
  addPlayerToPlayerCollision(
    player1: Phaser.Physics.Arcade.Sprite,
    player2: Phaser.Physics.Arcade.Sprite,
    onCollide: () => void
  ): Phaser.Physics.Arcade.Collider {
    return this.scene.physics.add.overlap(
      player1,
      player2,
      onCollide
    );
  }

  /**
   * Check if a player is on the ground
   */
  isOnGround(player: Phaser.Physics.Arcade.Sprite): boolean {
    return player.body?.blocked.down ?? false;
  }

  /**
   * Get the platform group for external use
   */
  getPlatformGroup(): Phaser.Physics.Arcade.StaticGroup {
    return this.platformGroup;
  }

  /**
   * Clear all platforms
   */
  clear(): void {
    this.platformGroup.clear(true, true);
  }

  destroy(): void {
    this.clear();
  }
}
