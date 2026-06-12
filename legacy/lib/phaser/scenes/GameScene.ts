import * as Phaser from 'phaser';
import { useGameStore } from '@/lib/game/state';
import { gameManager } from '@/lib/game/GameManager';
import { PlatformSprite } from '@/lib/phaser/entities/Platform';
import { InputSystem } from '@/lib/phaser/systems/InputSystem';
import { CollisionSystem } from '@/lib/phaser/systems/CollisionSystem';
import { AbilityController } from '@/lib/phaser/systems/AbilityController';
import { TagSystem } from '@/lib/phaser/systems/TagSystem';
import { PlayerManager } from '@/lib/phaser/systems/PlayerManager';
import { GameHUD } from '@/lib/phaser/ui/GameHUD';
import { GAME_CONFIG } from '@/lib/game/constants';
import { MapData } from '@/lib/game/maps';
import { gameSocket } from '@/lib/game/socket'; // Import socket client

/**
 * Main game scene - orchestrates all game systems
 */
export class GameScene extends Phaser.Scene {
  // Systems
  private inputSystem!: InputSystem
  private collisionSystem!: CollisionSystem;
  private abilityController!: AbilityController;
  private tagSystem!: TagSystem;
  private playerManager!: PlayerManager;
  private hud!: GameHUD;

  // Map
  private mapData: MapData | null = null;
  private platformSprites: PlatformSprite[] = [];

  // State
  private unsubscribeStore: (() => void) | null = null;
  private gameEnded: boolean = false;
  private unsubscribeSocket: (() => void) | null = null;

  constructor() {
    super('GameScene');
  }

  async create() {
    this.gameEnded = false;

    // Initialize systems
    this.initializeSystems();

    // Setup map
    this.createMap();

    // Setup collisions
    this.collisionSystem.setupCollisions(
      this.playerManager.getPlayerGroup(),
      this.platformSprites.map(p => p.sprite)
    );

    // Setup UI
    this.hud.create();

    // Connect to game server
    try {
      const playerId = await gameSocket.connect();
      
      // Set local player ID in manager (server assigns it now)
      // We might need to adjust PlayerManager to accept an ID or just trust the socket
      
      // Listen for state updates
      this.unsubscribeSocket = gameSocket.onStateUpdate((state) => {
        // Update all players based on server state
        this.playerManager.syncState(state.players);
      });

    } catch (err) {
      console.error("Failed to connect to game server:", err);
    }
  }

  update(_time: number, delta: number) {
    const localPlayerId = gameSocket.playerId;
    if (!localPlayerId || this.gameEnded) return;

    // Handle input
    const input = this.inputSystem.getInputState();
    
    // Send input to server
    gameSocket.sendInput({
        up: input.up,
        down: input.down,
        left: input.left,
        right: input.right,
        jump: input.jump
    });

    // Note: We no longer update local physics or sync to DB here. 
    // The server sends us the true position, and we render it in the socket callback.
    
    // Update abilities (client-side prediction/visuals only for now)
    this.abilityController.update(delta);
    
    // Update UI
    this.updateUI();
  }

  shutdown() {
    this.unsubscribeStore?.();
    this.unsubscribeSocket?.();
    gameSocket.disconnect();
    
    this.inputSystem?.destroy();
    this.tagSystem?.destroy();
    this.abilityController?.destroy();
    
    // Cleanup sprites
    this.platformSprites.forEach(p => p.destroy());
    this.playerManager.destroy();
  }

  private initializeSystems() {
    this.inputSystem = new InputSystem(this);
    this.collisionSystem = new CollisionSystem(this);
    this.abilityController = new AbilityController(this);
    this.tagSystem = new TagSystem();
    this.playerManager = new PlayerManager(this);
    this.hud = new GameHUD(this);
  }

  private createMap() {
    // Create ground
    const ground = new PlatformSprite(this, 400, 568, 800, 64, true);
    this.platformSprites.push(ground);
    
    // Create some ledges
    this.platformSprites.push(new PlatformSprite(this, 600, 400, 200, 32));
    this.platformSprites.push(new PlatformSprite(this, 50, 250, 200, 32));
    this.platformSprites.push(new PlatformSprite(this, 750, 220, 200, 32));
  }

  private updateUI() {
    const localPlayer = this.playerManager.getLocalPlayer();
    if (localPlayer) {
      this.hud.update({
        isIt: localPlayer.isIt,
        abilityCooldown: this.abilityController.getCooldown(),
        abilityName: this.abilityController.getAbilityName(),
        gameStatus: 'playing', // Hardcoded for now
        timer: 0
      });
    }
  }
}
