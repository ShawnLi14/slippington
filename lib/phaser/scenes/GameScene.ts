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

/**
 * Main game scene - orchestrates all game systems
 */
export class GameScene extends Phaser.Scene {
  // Systems
  private inputSystem!: InputSystem;
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

  constructor() {
    super('GameScene');
  }

  async create() {
    this.gameEnded = false;

    // Initialize systems
    this.initializeSystems();
    
    // Set up world
    this.setupWorld();
    
    // Create UI
    this.hud.create();

    // Connect to game
    await this.connectToGame();
  }

  update(_time: number, delta: number) {
    const localPlayer = this.playerManager.getLocalPlayer();
    const localPlayerId = this.playerManager.getLocalPlayerId();
    
    if (!localPlayer || !localPlayerId || this.gameEnded) return;

    // Update systems
    this.abilityController.update(delta);
    this.tagSystem.update(delta);

    // Handle input
    this.handleInput();

    // Check for tagging
    this.tagSystem.checkTagging(
      localPlayer,
      localPlayerId,
      this.playerManager.getRemotePlayers()
    );

    // Update UI
    this.updateUI();

    // Sync position to server
    gameManager.updatePosition(
      localPlayerId,
      localPlayer.x,
      localPlayer.y,
      localPlayer.velocityY,
      localPlayer.facingRight
    );
  }

  shutdown() {
    this.unsubscribeStore?.();
    this.inputSystem?.destroy();
    this.collisionSystem?.destroy();
    this.abilityController?.destroy();
    this.tagSystem?.destroy();
    this.playerManager?.destroy();
    this.hud?.destroy();
    
    window.removeEventListener('beforeunload', this.handleUnload);
    
    const localPlayerId = this.playerManager?.getLocalPlayerId();
    if (localPlayerId) {
      gameManager.leaveGame(localPlayerId);
    }
  }

  // ============================================
  // Initialization
  // ============================================

  private initializeSystems(): void {
    this.inputSystem = new InputSystem(this);
    this.collisionSystem = new CollisionSystem(this);
    this.abilityController = new AbilityController(this);
    this.tagSystem = new TagSystem(this);
    this.playerManager = new PlayerManager(this, this.collisionSystem);
    this.hud = new GameHUD(this);
  }

  private setupWorld(): void {
    // Set world bounds
    this.physics.world.setBounds(0, 0, GAME_CONFIG.MAP_WIDTH, GAME_CONFIG.MAP_HEIGHT);

    // Draw background
    this.add.rectangle(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2,
      GAME_CONFIG.MAP_WIDTH,
      GAME_CONFIG.MAP_HEIGHT,
      0x1a1a2e
    );

    // Draw border
    const border = this.add.graphics();
    border.lineStyle(4, 0x4ecdc4, 0.3);
    border.strokeRect(2, 2, GAME_CONFIG.MAP_WIDTH - 4, GAME_CONFIG.MAP_HEIGHT - 4);
  }

  private async connectToGame(): Promise<void> {
    const loadingText = this.add.text(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2,
      'Connecting...',
      { fontSize: '32px', color: '#ffffff' }
    ).setOrigin(0.5);

    try {
      const existingGameId = useGameStore.getState().gameId;
      const { gameId, playerId, mapData } = await gameManager.joinOrCreateGame(existingGameId);
      
      this.playerManager.setLocalPlayerId(playerId);
      this.mapData = mapData;

      // Create platforms
      this.createPlatforms(mapData);

      // Subscribe to game updates
      await gameManager.subscribeToGame(gameId);
      loadingText.destroy();

      // Subscribe to state changes
      this.unsubscribeStore = useGameStore.subscribe((state) => {
        this.playerManager.syncPlayers(state.players);
        this.checkGameEnd(state.status, state.timerEnd);
      });
      this.playerManager.syncPlayers(useGameStore.getState().players);

      // Handle page unload
      window.addEventListener('beforeunload', this.handleUnload);

    } catch (error) {
      loadingText.setText('Failed to connect.\nRefresh to retry.');
      console.error('Failed to join game:', error);
    }
  }

  // ============================================
  // Input Handling
  // ============================================

  private handleInput(): void {
    const localPlayer = this.playerManager.getLocalPlayer();
    if (!localPlayer) return;

    const input = this.inputSystem.getState();
    const speed = localPlayer.getMoveSpeed();

    // Horizontal movement
    if (input.left) {
      localPlayer.setVelocityX(-speed);
    } else if (input.right) {
      localPlayer.setVelocityX(speed);
    } else {
      localPlayer.setVelocityX(0);
    }

    // Jumping
    if (this.inputSystem.isJumpJustPressed() && localPlayer.isOnGround()) {
      localPlayer.jump();
    }

    // Ability (Q key)
    if (input.primaryAbility) {
      const playerId = this.playerManager.getLocalPlayerId();
      if (playerId) {
        this.abilityController.tryUseAbility(localPlayer, playerId);
      }
    }
  }

  // ============================================
  // UI Updates
  // ============================================

  private updateUI(): void {
    const state = useGameStore.getState();
    const playerCount = Object.keys(state.players).length;
    
    this.hud.updateTimer(state.timerEnd, playerCount);
    this.hud.updateAbility(
      this.abilityController.getCooldown(),
      this.abilityController.getMaxCooldown()
    );
  }

  // ============================================
  // Game State
  // ============================================

  private checkGameEnd(status: string, timerEnd: string | null): void {
    if (this.gameEnded) return;

    if (status === 'finished' || (timerEnd && new Date(timerEnd).getTime() <= Date.now())) {
      this.endGame();
    }
  }

  private endGame(): void {
    this.gameEnded = true;

    const state = useGameStore.getState();
    const players = Object.values(state.players);
    const itPlayer = players.find(p => p.is_it);
    const localPlayerId = this.playerManager.getLocalPlayerId();
    
    let title = 'Game Over!';
    let subtitle = '';
    
    if (players.length <= 1) {
      subtitle = 'Not enough players';
    } else if (itPlayer) {
      const isLocalIt = itPlayer.id === localPlayerId;
      
      if (isLocalIt) {
        title = 'YOU LOSE!';
        subtitle = 'You were "it" when time ran out';
      } else {
        title = 'YOU WIN!';
        subtitle = 'You escaped being "it"!';
      }
    }

    this.hud.showGameOver(title, subtitle, () => window.location.reload());
  }

  // ============================================
  // Map Setup
  // ============================================

  private createPlatforms(mapData: MapData): void {
    for (const platform of mapData.platforms) {
      const sprite = new PlatformSprite(this, platform);
      this.platformSprites.push(sprite);
    }

    this.collisionSystem.createPlatforms(mapData.platforms);
  }

  // ============================================
  // Event Handlers
  // ============================================

  private handleUnload = () => {
    const localPlayerId = this.playerManager?.getLocalPlayerId();
    if (localPlayerId) {
      gameManager.leaveGame(localPlayerId);
    }
  };
}
