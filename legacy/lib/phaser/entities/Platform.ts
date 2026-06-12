import * as Phaser from 'phaser';
import { Platform as PlatformData } from '@/lib/game/maps/types';

/**
 * Visual representation of a platform
 */
export class PlatformSprite {
  private scene: Phaser.Scene;
  private graphics: Phaser.GameObjects.Graphics;
  private data: PlatformData;

  constructor(scene: Phaser.Scene, data: PlatformData) {
    this.scene = scene;
    this.data = data;
    this.graphics = scene.add.graphics();
    this.draw();
  }

  private draw(): void {
    const { x, y, width, height, type } = this.data;

    // Platform colors based on type
    const colors = {
      solid: { fill: 0x5a5a7a, stroke: 0x7a7a9a },
      passthrough: { fill: 0x4a4a6a, stroke: 0x6a6a8a },
      moving: { fill: 0x6a5a7a, stroke: 0x8a7a9a },
      crumbling: { fill: 0x7a5a5a, stroke: 0x9a7a7a },
    };

    const color = colors[type] || colors.solid;

    // Draw platform
    this.graphics.fillStyle(color.fill, 1);
    this.graphics.fillRoundedRect(x, y, width, height, 4);

    // Draw border
    this.graphics.lineStyle(2, color.stroke, 1);
    this.graphics.strokeRoundedRect(x, y, width, height, 4);

    // Add visual indicator for passthrough platforms
    if (type === 'passthrough') {
      this.graphics.lineStyle(1, color.stroke, 0.5);
      const dashLength = 10;
      for (let i = x + 5; i < x + width - 5; i += dashLength * 2) {
        this.graphics.lineBetween(i, y + height / 2, i + dashLength, y + height / 2);
      }
    }
  }

  destroy(): void {
    this.graphics.destroy();
  }
}

