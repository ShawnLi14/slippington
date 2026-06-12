import * as Phaser from 'phaser';
import { PlayerSprite } from '@/lib/phaser/entities/PlayerSprite';
import { gameManager } from '@/lib/game/GameManager';
import { useGameStore } from '@/lib/game/state';
import { GAME_CONFIG } from '@/lib/game/constants';

/**
 * Handles tag collision detection and tag transfer
 */
export class TagSystem {
  private scene: Phaser.Scene;
  private collidingPlayers: Set<string> = new Set();
  private tagCooldown: number = 0;

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
  }

  /**
   * Update tag cooldown
   */
  update(delta: number): void {
    if (this.tagCooldown > 0) {
      this.tagCooldown -= delta;
    }
  }

  /**
   * Check for tag collisions between local player and remote players
   * Only checks if local player is "it"
   */
  checkTagging(
    localPlayer: PlayerSprite,
    localPlayerId: string,
    remotePlayers: Map<string, PlayerSprite>
  ): void {
    if (!localPlayer.isIt || this.tagCooldown > 0) return;
    
    for (const [remoteId, remotePlayer] of remotePlayers) {
      if (remotePlayer.isIt) continue;

      const distance = Phaser.Math.Distance.Between(
        localPlayer.x, localPlayer.y,
        remotePlayer.x, remotePlayer.y
      );

      const tagRange = GAME_CONFIG.PLAYER_SIZE;

      if (distance < tagRange) {
        // Currently colliding
        if (!this.collidingPlayers.has(remoteId)) {
          // ENTERING collision -> trigger tag
          this.collidingPlayers.add(remoteId);
          this.performTag(localPlayerId, remoteId, localPlayer);
        }
      } else {
        // Not colliding - reset state
        this.collidingPlayers.delete(remoteId);
      }
    }
  }

  private async performTag(
    taggerId: string,
    taggedId: string,
    localPlayer: PlayerSprite
  ): Promise<void> {
    this.tagCooldown = GAME_CONFIG.TAG_COOLDOWN;

    try {
      const success = await gameManager.tagPlayer(taggerId, taggedId);
      
      if (success) {
        const state = useGameStore.getState();
        if (!state.timerEnd && state.gameId) {
          await gameManager.startGame(state.gameId);
        }

        this.showTagEffect(localPlayer.x, localPlayer.y);
      }
    } catch (error) {
      console.error('Failed to perform tag:', error);
    }
  }

  private showTagEffect(x: number, y: number): void {
    // Flash effect
    this.scene.cameras.main.flash(100, 255, 100, 100);
    
    // "TAG!" text
    const tagText = this.scene.add.text(x, y - 80, 'TAG!', {
      fontSize: '32px',
      color: '#ff4444',
      fontStyle: 'bold',
    }).setOrigin(0.5);

    this.scene.tweens.add({
      targets: tagText,
      y: tagText.y - 50,
      alpha: 0,
      duration: 800,
      ease: 'Power2',
      onComplete: () => tagText.destroy(),
    });
  }

  /**
   * Clear collision tracking (e.g., when player disconnects)
   */
  clearPlayer(playerId: string): void {
    this.collidingPlayers.delete(playerId);
  }

  destroy(): void {
    this.collidingPlayers.clear();
  }
}

