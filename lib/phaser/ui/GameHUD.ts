import * as Phaser from 'phaser';
import { GAME_CONFIG } from '@/lib/game/constants';

/**
 * Handles all in-game UI elements
 */
export class GameHUD {
  private scene: Phaser.Scene;
  
  // Timer UI
  private timerText: Phaser.GameObjects.Text | null = null;
  
  // Ability UI
  private abilityUI: {
    container: Phaser.GameObjects.Container;
    cooldownBar: Phaser.GameObjects.Rectangle;
    cooldownText: Phaser.GameObjects.Text;
    keyText: Phaser.GameObjects.Text;
  } | null = null;
  
  // Game over UI
  private gameOverContainer: Phaser.GameObjects.Container | null = null;

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
  }

  create(): void {
    this.createTimerUI();
    this.createAbilityUI();
  }

  private createTimerUI(): void {
    const timerBg = this.scene.add.rectangle(
      GAME_CONFIG.MAP_WIDTH / 2, 40, 200, 50, 0x000000, 0.5
    );
    timerBg.setStrokeStyle(2, 0x4ecdc4);

    this.timerText = this.scene.add.text(
      GAME_CONFIG.MAP_WIDTH / 2, 40, 'WAITING...', {
        fontSize: '24px',
        color: '#ffffff',
        fontStyle: 'bold',
      }
    ).setOrigin(0.5);
  }

  private createAbilityUI(): void {
    const x = GAME_CONFIG.MAP_WIDTH - 100;
    const y = GAME_CONFIG.MAP_HEIGHT - 80;

    const container = this.scene.add.container(x, y);

    // Background
    const bg = this.scene.add.rectangle(0, 0, 80, 80, 0x000000, 0.7);
    bg.setStrokeStyle(2, 0x4ecdc4);
    container.add(bg);

    // Ability name
    const nameText = this.scene.add.text(0, -25, 'BLINK', {
      fontSize: '12px',
      color: '#4ecdc4',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    container.add(nameText);

    // Cooldown bar background
    const barBg = this.scene.add.rectangle(0, 5, 60, 8, 0x333333);
    container.add(barBg);

    // Cooldown bar fill
    const cooldownBar = this.scene.add.rectangle(-30, 5, 60, 8, 0x4ecdc4);
    cooldownBar.setOrigin(0, 0.5);
    container.add(cooldownBar);

    // Cooldown text
    const cooldownText = this.scene.add.text(0, 5, 'READY', {
      fontSize: '10px',
      color: '#ffffff',
    }).setOrigin(0.5);
    container.add(cooldownText);

    // Key hint
    const keyText = this.scene.add.text(0, 28, '[Q]', {
      fontSize: '14px',
      color: '#888888',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    container.add(keyText);

    this.abilityUI = { container, cooldownBar, cooldownText, keyText };
  }

  updateTimer(timerEnd: string | null, playerCount: number): void {
    if (!this.timerText) return;

    if (timerEnd) {
      const remaining = Math.max(0, new Date(timerEnd).getTime() - Date.now());
      const seconds = Math.ceil(remaining / 1000);
      
      if (seconds > 0) {
        this.timerText.setText(`${seconds}s`);
        this.timerText.setColor(seconds <= 10 ? '#ff4444' : '#ffffff');
      } else {
        this.timerText.setText('TIME!');
      }
    } else {
      this.timerText.setText(`${playerCount} player${playerCount !== 1 ? 's' : ''}`);
    }
  }

  updateAbility(cooldown: number, maxCooldown: number): void {
    if (!this.abilityUI) return;

    const { cooldownBar, cooldownText, keyText } = this.abilityUI;

    if (cooldown > 0) {
      const progress = 1 - (cooldown / maxCooldown);
      cooldownBar.width = 60 * progress;
      cooldownBar.setFillStyle(0x666666);
      
      const secondsLeft = Math.ceil(cooldown / 1000);
      cooldownText.setText(`${secondsLeft}s`);
      cooldownText.setColor('#ff6666');
      keyText.setColor('#444444');
    } else {
      cooldownBar.width = 60;
      cooldownBar.setFillStyle(0x4ecdc4);
      cooldownText.setText('READY');
      cooldownText.setColor('#4ecdc4');
      keyText.setColor('#4ecdc4');
    }
  }

  showGameOver(title: string, subtitle: string, onPlayAgain: () => void): void {
    // Darken background
    this.scene.add.rectangle(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2,
      GAME_CONFIG.MAP_WIDTH,
      GAME_CONFIG.MAP_HEIGHT,
      0x000000,
      0.7
    );

    this.gameOverContainer = this.scene.add.container(
      GAME_CONFIG.MAP_WIDTH / 2,
      GAME_CONFIG.MAP_HEIGHT / 2
    );

    // Background panel
    const panel = this.scene.add.rectangle(0, 0, 500, 300, 0x1a1a2e);
    panel.setStrokeStyle(4, 0x4ecdc4);
    this.gameOverContainer.add(panel);

    // Title
    const titleText = this.scene.add.text(0, -80, title, {
      fontSize: '48px',
      color: title === 'YOU WIN!' ? '#4ecdc4' : '#ff4444',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    this.gameOverContainer.add(titleText);

    // Subtitle
    const subTextObj = this.scene.add.text(0, -20, subtitle, {
      fontSize: '20px',
      color: '#ffffff',
    }).setOrigin(0.5);
    this.gameOverContainer.add(subTextObj);

    // Play again button
    const buttonBg = this.scene.add.rectangle(0, 60, 200, 50, 0x4ecdc4);
    buttonBg.setInteractive({ useHandCursor: true });
    this.gameOverContainer.add(buttonBg);

    const buttonText = this.scene.add.text(0, 60, 'PLAY AGAIN', {
      fontSize: '20px',
      color: '#0a0a12',
      fontStyle: 'bold',
    }).setOrigin(0.5);
    this.gameOverContainer.add(buttonText);

    buttonBg.on('pointerover', () => buttonBg.setFillStyle(0x5eddd4));
    buttonBg.on('pointerout', () => buttonBg.setFillStyle(0x4ecdc4));
    buttonBg.on('pointerdown', onPlayAgain);

    // Animate in
    this.gameOverContainer.setScale(0);
    this.scene.tweens.add({
      targets: this.gameOverContainer,
      scale: 1,
      duration: 300,
      ease: 'Back.easeOut',
    });
  }

  destroy(): void {
    this.timerText?.destroy();
    this.abilityUI?.container.destroy();
    this.gameOverContainer?.destroy();
  }
}

