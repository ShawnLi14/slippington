import * as Phaser from 'phaser';
import { PlayerSprite } from '@/lib/phaser/entities/PlayerSprite';
import { Ability, AbilityContext } from '@/lib/game/abilities/types';
import { BlinkAbility } from '@/lib/game/abilities/BlinkAbility';

/**
 * Handles ability input, cooldowns, and execution
 * Uses ability definitions from lib/game/abilities
 */
export class AbilityController {
  private scene: Phaser.Scene;
  private ability: Ability;
  private cooldown: number = 0;

  constructor(scene: Phaser.Scene, ability: Ability = BlinkAbility) {
    this.scene = scene;
    this.ability = ability;
  }

  /**
   * Update cooldown timer
   */
  update(delta: number): void {
    if (this.cooldown > 0) {
      this.cooldown -= delta;
    }
  }

  /**
   * Check if ability is ready
   */
  isReady(): boolean {
    return this.cooldown <= 0;
  }

  /**
   * Get current cooldown value
   */
  getCooldown(): number {
    return this.cooldown;
  }

  /**
   * Get max cooldown for UI
   */
  getMaxCooldown(): number {
    return this.ability.cooldown;
  }

  /**
   * Get ability name for UI
   */
  getAbilityName(): string {
    return this.ability.name;
  }

  /**
   * Try to use the ability
   * Returns true if ability was used
   */
  tryUseAbility(player: PlayerSprite, playerId: string): boolean {
    if (!this.isReady()) return false;

    // Build context for ability execution
    const context: AbilityContext = {
      scene: this.scene,
      playerId,
      playerX: player.x,
      playerY: player.y,
      facingRight: player.facingRight,
      setPlayerPosition: (x: number, y: number) => {
        player.gameObject.setPosition(x, y);
      },
    };

    // Execute the ability
    const result = this.ability.execute(context);

    if (result.success) {
      this.cooldown = this.ability.cooldown;
    }

    return result.success;
  }

  destroy(): void {
    // Nothing to clean up
  }
}
