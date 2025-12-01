import * as Phaser from 'phaser';
import { PlayerSprite } from '@/lib/phaser/entities/PlayerSprite';
import { CollisionSystem } from './CollisionSystem';
import { Player } from '@/lib/game/types';
import { PlayerClassId } from '@/lib/game/classes';

/**
 * Manages creation, syncing, and destruction of player sprites
 */
export class PlayerManager {
  private scene: Phaser.Scene;
  private collisionSystem: CollisionSystem;
  
  private localPlayer: PlayerSprite | null = null;
  private localPlayerId: string | null = null;
  private remotePlayers: Map<string, PlayerSprite> = new Map();

  constructor(scene: Phaser.Scene, collisionSystem: CollisionSystem) {
    this.scene = scene;
    this.collisionSystem = collisionSystem;
  }

  /**
   * Set the local player ID (called after joining game)
   */
  setLocalPlayerId(id: string): void {
    this.localPlayerId = id;
  }

  /**
   * Get the local player sprite
   */
  getLocalPlayer(): PlayerSprite | null {
    return this.localPlayer;
  }

  /**
   * Get the local player ID
   */
  getLocalPlayerId(): string | null {
    return this.localPlayerId;
  }

  /**
   * Get all remote player sprites
   */
  getRemotePlayers(): Map<string, PlayerSprite> {
    return this.remotePlayers;
  }

  /**
   * Sync player state from server
   */
  syncPlayers(players: Record<string, Player>): void {
    const currentIds = new Set(Object.keys(players));

    // Remove disconnected players
    for (const [id, sprite] of this.remotePlayers) {
      if (!currentIds.has(id)) {
        sprite.destroy();
        this.remotePlayers.delete(id);
      }
    }

    // Add or update players
    for (const [id, data] of Object.entries(players)) {
      if (id === this.localPlayerId) {
        if (!this.localPlayer) {
          this.createLocalPlayer(data);
        } else {
          this.localPlayer.updateAppearance(data.color, data.is_it);
        }
      } else {
        this.syncRemotePlayer(id, data);
      }
    }
  }

  private createLocalPlayer(data: Player): void {
    const classId = (data.class_id as PlayerClassId) || 'slipper';
    
    this.localPlayer = new PlayerSprite({
      scene: this.scene,
      x: data.x,
      y: data.y,
      color: data.color,
      isIt: data.is_it,
      isLocal: true,
      classId,
    });

    // Set up collision with platforms
    this.collisionSystem.addPlayerCollision(this.localPlayer.gameObject);
  }

  private syncRemotePlayer(id: string, data: Player): void {
    const existing = this.remotePlayers.get(id);
    
    if (existing) {
      existing.moveTo(data.x, data.y);
      existing.setFacingRight(data.facing_right);
      existing.updateAppearance(data.color, data.is_it);
    } else {
      const classId = (data.class_id as PlayerClassId) || 'slipper';
      
      const sprite = new PlayerSprite({
        scene: this.scene,
        x: data.x,
        y: data.y,
        color: data.color,
        isIt: data.is_it,
        isLocal: false,
        classId,
      });
      sprite.setFacingRight(data.facing_right);
      this.remotePlayers.set(id, sprite);
    }
  }

  destroy(): void {
    this.localPlayer?.destroy();
    this.localPlayer = null;
    
    for (const sprite of this.remotePlayers.values()) {
      sprite.destroy();
    }
    this.remotePlayers.clear();
  }
}

