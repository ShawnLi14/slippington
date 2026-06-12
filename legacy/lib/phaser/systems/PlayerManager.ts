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
  syncState(players: Record<string, any>): void {
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
      // Skip if this is the local player ID, but we still need to update visual position
      // because the SERVER is now authoritative over physics.
      // In a Client-Predicted model, we would reconcile here.
      // For now, we will just snap the local player to the server position too
      // to ensure we don't drift (simple "dumb terminal" client).
      
      if (id === this.localPlayerId) {
        if (!this.localPlayer) {
          this.createLocalPlayer(data);
        } else {
           // SNAP to server position (for now)
          this.localPlayer.gameObject.setPosition(data.x, data.y);
          this.localPlayer.setFacingRight(data.facingRight);
          this.localPlayer.updateAppearance(data.color, data.isIt);
        }
      } else {
        this.syncRemotePlayer(id, data);
      }
    }
  }

  private createLocalPlayer(data: any): void {
    const classId = (data.classId as PlayerClassId) || 'slipper';
    
    this.localPlayer = new PlayerSprite({
      scene: this.scene,
      x: data.x,
      y: data.y,
      color: data.color,
      isIt: data.isIt,
      isLocal: true,
      classId,
    });

    // Set up collision with platforms
    // Note: collisions are now server-side, but client-side collision 
    // is still useful for prediction/smoothness if we enable physics on client.
    // For "dumb terminal" mode, we might disable client physics bodies.
    this.collisionSystem.addPlayerCollision(this.localPlayer.gameObject);
  }

  private syncRemotePlayer(id: string, data: any): void {
    const existing = this.remotePlayers.get(id);
    
    if (existing) {
      // Interpolation would happen here in a more advanced version
      existing.gameObject.setPosition(data.x, data.y); 
      existing.setFacingRight(data.facingRight);
      existing.updateAppearance(data.color, data.isIt);
    } else {
      const classId = (data.classId as PlayerClassId) || 'slipper';
      
      const sprite = new PlayerSprite({
        scene: this.scene,
        x: data.x,
        y: data.y,
        color: data.color,
        isIt: data.isIt,
        isLocal: false,
        classId,
      });
      sprite.setFacingRight(data.facingRight);
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

  /**
   * Get the group of all player sprites
   */
  getPlayerGroup(): Phaser.GameObjects.Group {
     return this.scene.physics.add.group(
        [this.localPlayer?.gameObject, ...Array.from(this.remotePlayers.values()).map(p => p.gameObject)].filter((p): p is Phaser.Types.Physics.Arcade.SpriteWithDynamicBody => !!p)
     );
  }
}
