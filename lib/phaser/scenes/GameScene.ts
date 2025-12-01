import * as Phaser from 'phaser';
import { useGameStore } from '@/lib/game/state';
import { gameManager } from '@/lib/game/GameManager';
import { PlayerSprite } from '@/lib/phaser/entities/PlayerSprite';
import { PlatformSprite } from '@/lib/phaser/entities/Platform';
import { InputSystem } from '@/lib/phaser/systems/InputSystem';
import { CollisionSystem } from '@/lib/phaser/systems/CollisionSystem';
import { GAME_CONFIG } from '@/lib/game/constants';
import { Player } from '@/lib/game/types';
import { MapData } from '@/lib/game/maps';
import { PlayerClassId } from '@/lib/game/classes';

/**
 * Main game scene - handles rendering, input, and physics
 * Delegates game state to GameManager
 */
export class GameScene extends Phaser.Scene {
  // Systems
  private inputSystem!: InputSystem;
  private collisionSystem!: CollisionSystem;

  // Remote players map
  private remotePlayers: Map<string, PlayerSprite> = new Map();
  
  // Track collision state to detect edges (entering collision)
  private collidingPlayers: Set<string> = new Set();
  private platformSprites: PlatformSprite[] = [];

  // Map data
  private mapData: MapData | null = null;

  // UI elements
  private timerText: Phaser.GameObjects.Text | null = null;
  private gameOverContainer: Phaser.GameObjects.Container | null = null;

  // Game state
  private unsubscribeStore: (() => void) | null = null;
  private tagCooldown: number = 0;
  private gameEnded: boolean = false;

  constructor() {
    super('GameScene');
  }

  async create() {
    // Reset state
    this.gameEnded = false;
    this.tagCooldown = 0;

    // Initialize systems
    this.inputSystem = new InputSystem(this);
    this.collisionSystem = new CollisionSystem(this);

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

    // Create timer UI
    this.createTimerUI();

    // Loading text
    const loadingText = this.add.text(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2,
      'Connecting...',
      { fontSize: '32px', color: '#ffffff' }
    ).setOrigin(0.5);

    try {
      // Check if we're joining a specific game from the menu
      const existingGameId = useGameStore.getState().gameId;
      
      // Join game and get map data
      const { gameId, playerId, mapData } = await gameManager.joinOrCreateGame(existingGameId);
      this.localPlayerId = playerId;
      this.mapData = mapData;

      // Create platforms from map data
      this.createPlatforms(mapData);

      // Subscribe to game updates
      await gameManager.subscribeToGame(gameId);
      loadingText.destroy();

      // Subscribe to state changes
      this.unsubscribeStore = useGameStore.subscribe((state) => {
        this.syncPlayers(state.players);
        this.checkGameEnd(state.status, state.timerEnd);
      });
      this.syncPlayers(useGameStore.getState().players);

      // Handle page unload
      window.addEventListener('beforeunload', this.handleUnload);

    } catch (error) {
      loadingText.setText('Failed to connect.\nRefresh to retry.');
      console.error('Failed to join game:', error);
    }
  }

  update(time: number, delta: number) {
    if (!this.localPlayer || !this.localPlayerId || this.gameEnded) return;

    // Update tag cooldown
    if (this.tagCooldown > 0) {
      this.tagCooldown -= delta;
    }

    // Handle input
    this.handleInput();

    // Check for tagging (only if local player is "it")
    if (this.localPlayer.isIt) {
      this.checkTagging();
    }

    // Update timer display
    this.updateTimerDisplay();

    // Sync position to server
    gameManager.updatePosition(
      this.localPlayerId,
      this.localPlayer.x,
      this.localPlayer.y,
      this.localPlayer.velocityY,
      this.localPlayer.facingRight
    );
  }

  shutdown() {
    this.unsubscribeStore?.();
    this.inputSystem?.destroy();
    this.collisionSystem?.destroy();
    window.removeEventListener('beforeunload', this.handleUnload);
    if (this.localPlayerId) {
      gameManager.leaveGame(this.localPlayerId);
    }
  }

  private createTimerUI(): void {
    // Timer background
    const timerBg = this.add.rectangle(GAME_CONFIG.MAP_WIDTH / 2, 40, 200, 50, 0x000000, 0.5);
    timerBg.setStrokeStyle(2, 0x4ecdc4);

    // Timer text
    this.timerText = this.add.text(GAME_CONFIG.MAP_WIDTH / 2, 40, 'WAITING...', {
      fontSize: '24px',
      color: '#ffffff',
      fontStyle: 'bold',
    }).setOrigin(0.5);
  }

  private updateTimerDisplay(): void {
    const state = useGameStore.getState();
    
    if (!this.timerText) return;

    if (state.timerEnd) {
      const remaining = Math.max(0, new Date(state.timerEnd).getTime() - Date.now());
      const seconds = Math.ceil(remaining / 1000);
      
      if (seconds > 0) {
        this.timerText.setText(`${seconds}s`);
        // Change color when low on time
        if (seconds <= 10) {
          this.timerText.setColor('#ff4444');
        } else {
          this.timerText.setColor('#ffffff');
        }
      } else {
        this.timerText.setText('TIME!');
      }
    } else {
      // Show player count while waiting
      const playerCount = Object.keys(state.players).length;
      this.timerText.setText(`${playerCount} player${playerCount !== 1 ? 's' : ''}`);
    }
  }

  private handleInput(): void {
    const input = this.inputSystem.getState();
    const speed = this.localPlayer!.getMoveSpeed();

    // Horizontal movement
    if (input.left) {
      this.localPlayer!.setVelocityX(-speed);
    } else if (input.right) {
      this.localPlayer!.setVelocityX(speed);
    } else {
      this.localPlayer!.setVelocityX(0);
    }

    // Jumping
    if (this.inputSystem.isJumpJustPressed() && this.localPlayer!.isOnGround()) {
      this.localPlayer!.jump();
    }
  }

  private checkTagging(): void {
    if (!this.localPlayer || this.tagCooldown > 0) return;
    
    // Check collision with remote players
    for (const [remoteId, remotePlayer] of this.remotePlayers) {
      if (remotePlayer.isIt) continue;

      const distance = Phaser.Math.Distance.Between(
        this.localPlayer.x, this.localPlayer.y,
        remotePlayer.x, remotePlayer.y
      );

      const tagRange = GAME_CONFIG.PLAYER_SIZE; // Exact overlap

      if (distance < tagRange) {
        // Currently colliding
        if (!this.collidingPlayers.has(remoteId)) {
          // ENTERING collision -> trigger tag
          this.collidingPlayers.add(remoteId);
          this.performTag(remoteId);
        }
      } else {
        // Not colliding
        if (this.collidingPlayers.has(remoteId)) {
          // LEAVING collision -> reset state
          this.collidingPlayers.delete(remoteId);
        }
      }
    }
  }

  private async performTag(taggedId: string): Promise<void> {
    if (!this.localPlayerId) return;

    this.tagCooldown = GAME_CONFIG.TAG_COOLDOWN;

    try {
      const success = await gameManager.tagPlayer(this.localPlayerId, taggedId);
      
      if (success) {
        const state = useGameStore.getState();
        if (!state.timerEnd && state.gameId) {
          await gameManager.startGame(state.gameId);
        }

        this.showTagEffect();
      }
    } catch (error) {
      console.error('Failed to perform tag:', error);
    }
  }

  private showTagEffect(): void {
    // Flash effect
    this.cameras.main.flash(100, 255, 100, 100);
    
    // "TAG!" text
    const tagText = this.add.text(
      this.localPlayer!.x,
      this.localPlayer!.y - 80,
      'TAG!',
      { fontSize: '32px', color: '#ff4444', fontStyle: 'bold' }
    ).setOrigin(0.5);

    this.tweens.add({
      targets: tagText,
      y: tagText.y - 50,
      alpha: 0,
      duration: 800,
      ease: 'Power2',
      onComplete: () => tagText.destroy(),
    });
  }

  private checkGameEnd(status: string, timerEnd: string | null): void {
    if (this.gameEnded) return;

    if (status === 'finished' || (timerEnd && new Date(timerEnd).getTime() <= Date.now())) {
      this.endGame();
    }
  }

  private endGame(): void {
    this.gameEnded = true;

    // Find winner (player who is NOT "it" when time runs out)
    const state = useGameStore.getState();
    const players = Object.values(state.players);
    const itPlayer = players.find(p => p.is_it);
    
    // Determine result
    let winnerText = 'Game Over!';
    let subText = '';
    
    if (players.length <= 1) {
      subText = 'Not enough players';
    } else if (itPlayer) {
      const isLocalIt = itPlayer.id === this.localPlayerId;
      
      if (isLocalIt) {
        winnerText = 'YOU LOSE!';
        subText = 'You were "it" when time ran out';
      } else {
        winnerText = 'YOU WIN!';
        subText = 'You escaped being "it"!';
      }
    }

    this.showGameOverScreen(winnerText, subText);
  }

  private showGameOverScreen(title: string, subtitle: string): void {
    // Darken background
    this.add.rectangle(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2,
      GAME_CONFIG.MAP_WIDTH,
      GAME_CONFIG.MAP_HEIGHT,
      0x000000,
      0.7
    );

    // Container for game over UI
    this.gameOverContainer = this.add.container(GAME_CONFIG.MAP_WIDTH / 2, GAME_CONFIG.MAP_HEIGHT / 2);

    // Background panel
    const panel = this.add.rectangle(0, 0, 500, 300, 0x1a1a2e);
    panel.setStrokeStyle(4, 0x4ecdc4);
    this.gameOverContainer.add(panel);

    // Title
    const titleText = this.add.text(0, -80, title, {
      fontSize: '48px',
      color: title === 'YOU WIN!' ? '#4ecdc4' : '#ff4444',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    this.gameOverContainer.add(titleText);

    // Subtitle
    const subTextObj = this.add.text(0, -20, subtitle, {
      fontSize: '20px',
      color: '#ffffff',
    }).setOrigin(0.5);
    this.gameOverContainer.add(subTextObj);

    // Play again button
    const buttonBg = this.add.rectangle(0, 60, 200, 50, 0x4ecdc4);
    buttonBg.setInteractive({ useHandCursor: true });
    this.gameOverContainer.add(buttonBg);

    const buttonText = this.add.text(0, 60, 'PLAY AGAIN', {
      fontSize: '20px',
      color: '#0a0a12',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    this.gameOverContainer.add(buttonText);

    buttonBg.on('pointerover', () => buttonBg.setFillStyle(0x5eddd4));
    buttonBg.on('pointerout', () => buttonBg.setFillStyle(0x4ecdc4));
    buttonBg.on('pointerdown', () => {
      // Return to menu
      window.location.reload();
    });

    // Animate in
    this.gameOverContainer.setScale(0);
    this.tweens.add({
      targets: this.gameOverContainer,
      scale: 1,
      duration: 300,
      ease: 'Back.easeOut',
    });
  }

  private createPlatforms(mapData: MapData): void {
    // Create visual platforms
    for (const platform of mapData.platforms) {
      const sprite = new PlatformSprite(this, platform);
      this.platformSprites.push(sprite);
    }

    // Create physics platforms
    this.collisionSystem.createPlatforms(mapData.platforms);
  }

  private setupPlayerCollision(player: PlayerSprite): void {
    this.collisionSystem.addPlayerCollision(player.gameObject);
  }

  private syncPlayers(players: Record<string, Player>): void {
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
    const classId = (data.class_id as PlayerClassId) || 'speedster';
    
    this.localPlayer = new PlayerSprite({
      scene: this,
      x: data.x,
      y: data.y,
      color: data.color,
      isIt: data.is_it,
      isLocal: true,
      classId,
    });

    // Set up collision with platforms
    this.setupPlayerCollision(this.localPlayer);
  }

  private syncRemotePlayer(id: string, data: Player): void {
    const existing = this.remotePlayers.get(id);
    
    if (existing) {
      existing.moveTo(data.x, data.y, data.velocity_y);
      existing.setFacingRight(data.facing_right);
      existing.updateAppearance(data.color, data.is_it);
    } else {
      const classId = (data.class_id as PlayerClassId) || 'speedster';
      
      const sprite = new PlayerSprite({
        scene: this,
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

  private handleUnload = () => {
    if (this.localPlayerId) {
      gameManager.leaveGame(this.localPlayerId);
    }
  };
}
