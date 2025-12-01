import * as Phaser from 'phaser';
import { GAME_CONFIG } from '@/lib/game/constants';
import { PlayerClassId, getClass } from '@/lib/game/classes';

export interface PlayerSpriteConfig {
  scene: Phaser.Scene;
  x: number;
  y: number;
  color: string;
  isIt: boolean;
  isLocal: boolean;
  classId?: PlayerClassId;
  label?: string;
}

/**
 * Encapsulates player rendering, physics, and visual updates
 * Supports both local (physics-enabled) and remote (interpolated) players
 */
export class PlayerSprite {
  private scene: Phaser.Scene;
  private container: Phaser.GameObjects.Container;
  private sprite: Phaser.GameObjects.Sprite | Phaser.Physics.Arcade.Sprite;
  private label: Phaser.GameObjects.Text;
  private arrow: Phaser.GameObjects.Graphics | null = null;
  private isLocal: boolean;
  private currentColor: string;
  private currentIsIt: boolean;
  private classId: PlayerClassId;
  private _facingRight: boolean = true;

  // Interpolation state
  private targetX: number;
  private targetY: number;
  private targetVelocityX: number = 0;
  private targetVelocityY: number = 0;
  private lastUpdate: number = 0;

  constructor(config: PlayerSpriteConfig) {
    this.scene = config.scene;
    this.isLocal = config.isLocal;
    this.currentColor = config.color;
    this.currentIsIt = config.isIt;
    this.classId = config.classId || 'slipper';
    this.targetX = config.x;
    this.targetY = config.y;

    const textureKey = this.createTexture(config.color, config.isIt);

    if (config.isLocal) {
      // Local player uses physics sprite
      this.sprite = this.scene.physics.add.sprite(config.x, config.y, textureKey);
      const physicsSprite = this.sprite as Phaser.Physics.Arcade.Sprite;
      physicsSprite.setCollideWorldBounds(true);
      physicsSprite.setBounce(0);
      physicsSprite.setDrag(0);
      
      // Set physics body size
      physicsSprite.body?.setSize(GAME_CONFIG.PLAYER_SIZE - 8, GAME_CONFIG.PLAYER_SIZE - 4);
      physicsSprite.body?.setOffset(4, 4);

      // Container just for the label and arrow (sprite is separate for physics)
      this.container = this.scene.add.container(0, 0);
      this.label = this.scene.add.text(0, 0, config.label || 'YOU', {
        fontSize: '12px',
        color: '#ffffff',
        fontStyle: 'bold',
      }).setOrigin(0.5);
      this.container.add(this.label);

      // Create arrow indicator
      this.arrow = this.createArrow();
      this.arrow.setVisible(config.isIt);

      // Update label position each frame
      this.scene.events.on('update', this.updateLabelPosition, this);
    } else {
      // Remote players don't need physics
      this.container = this.scene.add.container(config.x, config.y);
      this.sprite = this.scene.add.sprite(0, 0, textureKey);
      this.container.add(this.sprite);

      this.label = this.scene.add.text(0, -GAME_CONFIG.PLAYER_SIZE / 2 - 10, '', {
        fontSize: '12px',
        color: '#ffffff',
      }).setOrigin(0.5);
      this.container.add(this.label);

      // Create arrow for remote players too
      this.arrow = this.createArrowForContainer();
      this.arrow.setVisible(config.isIt);
      this.container.add(this.arrow);

      // Update interpolation for remote players
      this.scene.events.on('update', this.updateInterpolation, this);
    }
  }

  private createArrow(): Phaser.GameObjects.Graphics {
    const arrow = this.scene.add.graphics();
    arrow.setDepth(100);
    this.drawArrow(arrow);
    return arrow;
  }

  private createArrowForContainer(): Phaser.GameObjects.Graphics {
    const arrow = this.scene.make.graphics({});
    this.drawArrow(arrow);
    arrow.setPosition(0, -GAME_CONFIG.PLAYER_SIZE / 2 - 30);
    return arrow;
  }

  private drawArrow(graphics: Phaser.GameObjects.Graphics): void {
    graphics.clear();
    // Draw a red downward-pointing arrow
    graphics.fillStyle(0xff4444, 1);
    graphics.beginPath();
    graphics.moveTo(0, 0);      // Tip of arrow
    graphics.lineTo(-10, -15);  // Left corner
    graphics.lineTo(-4, -15);   // Left inner
    graphics.lineTo(-4, -25);   // Left top
    graphics.lineTo(4, -25);    // Right top
    graphics.lineTo(4, -15);    // Right inner
    graphics.lineTo(10, -15);   // Right corner
    graphics.closePath();
    graphics.fillPath();
    
    // Add glow effect
    graphics.lineStyle(2, 0xff0000, 0.5);
    graphics.strokePath();
  }

  private updateLabelPosition = () => {
    if (this.isLocal && this.sprite) {
      this.label.setPosition(this.sprite.x, this.sprite.y - GAME_CONFIG.PLAYER_SIZE / 2 - 10);
      if (this.arrow) {
        this.arrow.setPosition(this.sprite.x, this.sprite.y - GAME_CONFIG.PLAYER_SIZE / 2 - 5);
      }
    }
  };

  private updateInterpolation = (time: number, delta: number) => {
    if (this.isLocal) return;

    // Smoothly move towards target position (0.2 factor = fast but smooth)
    const lerpFactor = 0.2;
    
    // Apply velocity prediction if we haven't received an update recently
    // This prevents "stuttering" when updates are delayed
    if (Date.now() - this.lastUpdate > GAME_CONFIG.POSITION_UPDATE_INTERVAL * 1.5) {
      this.targetX += (this.targetVelocityX * delta) / 1000;
      this.targetY += (this.targetVelocityY * delta) / 1000;
    }

    this.container.x = Phaser.Math.Linear(this.container.x, this.targetX, lerpFactor);
    this.container.y = Phaser.Math.Linear(this.container.y, this.targetY, lerpFactor);
  };

  // Position getters
  get x(): number {
    return this.isLocal ? this.sprite.x : this.container.x;
  }

  get y(): number {
    return this.isLocal ? this.sprite.y : this.container.y;
  }

  get velocityX(): number {
    return this.physicsBody?.velocity.x ?? 0;
  }

  get velocityY(): number {
    return this.physicsBody?.velocity.y ?? 0;
  }

  get facingRight(): boolean {
    return this._facingRight;
  }

  get physicsBody(): Phaser.Physics.Arcade.Body | null {
    if (this.isLocal && this.sprite instanceof Phaser.Physics.Arcade.Sprite) {
      return this.sprite.body as Phaser.Physics.Arcade.Body;
    }
    return null;
  }

  get gameObject(): Phaser.Physics.Arcade.Sprite {
    return this.sprite as Phaser.Physics.Arcade.Sprite;
  }

  get isIt(): boolean {
    return this.currentIsIt;
  }

  // Check if player is on the ground
  isOnGround(): boolean {
    return this.physicsBody?.blocked.down ?? false;
  }

  // Velocity setters
  setVelocity(x: number, y: number): void {
    if (this.isLocal && this.sprite instanceof Phaser.Physics.Arcade.Sprite) {
      this.sprite.setVelocity(x, y);
      this.updateFacing(x);
    }
  }

  setVelocityX(x: number): void {
    if (this.isLocal && this.sprite instanceof Phaser.Physics.Arcade.Sprite) {
      this.sprite.setVelocityX(x);
      this.updateFacing(x);
    }
  }

  setVelocityY(y: number): void {
    if (this.isLocal && this.sprite instanceof Phaser.Physics.Arcade.Sprite) {
      this.sprite.setVelocityY(y);
    }
  }

  // Jump with class-specific force
  jump(): void {
    if (!this.isOnGround()) return;
    
    const playerClass = getClass(this.classId);
    const jumpForce = GAME_CONFIG.JUMP_FORCE * playerClass.stats.jumpForce;
    this.setVelocityY(jumpForce);
  }

  // Get movement speed based on class
  getMoveSpeed(): number {
    const playerClass = getClass(this.classId);
    return GAME_CONFIG.PLAYER_SPEED * playerClass.stats.speed;
  }

  private updateFacing(velocityX: number): void {
    if (velocityX > 0) {
      this._facingRight = true;
      this.sprite.setFlipX(false);
    } else if (velocityX < 0) {
      this._facingRight = false;
      this.sprite.setFlipX(true);
    }
  }

  // Remote player interpolation
  moveTo(x: number, y: number, velocityY: number = 0): void {
    if (!this.isLocal) {
      // Calculate implied X velocity based on position change
      const timeSinceLast = Math.max(1, Date.now() - this.lastUpdate);
      this.targetVelocityX = (x - this.targetX) / (timeSinceLast / 1000);
      this.targetVelocityY = velocityY;

      this.targetX = x;
      this.targetY = y;
      this.lastUpdate = Date.now();
    }
  }

  // Update facing direction for remote players
  setFacingRight(facingRight: boolean): void {
    this._facingRight = facingRight;
    this.sprite.setFlipX(!facingRight);
  }

  updateAppearance(color: string, isIt: boolean): void {
    if (color !== this.currentColor || isIt !== this.currentIsIt) {
      this.currentColor = color;
      this.currentIsIt = isIt;

      const textureKey = this.createTexture(color, isIt);
      this.sprite.setTexture(textureKey);

      // Update arrow visibility
      if (this.arrow) {
        this.arrow.setVisible(isIt);
      }
    }
  }

  private createTexture(color: string, isIt: boolean): string {
    const key = `player_${color}_${isIt}`;

    if (this.scene.textures.exists(key)) {
      return key;
    }

    const graphics = this.scene.make.graphics({ x: 0, y: 0 });
    const colorNum = parseInt(color.replace('#', ''), 16);
    const size = GAME_CONFIG.PLAYER_SIZE;

    graphics.fillStyle(colorNum, 1);
    graphics.fillRoundedRect(0, 0, size, size, 8);

    if (isIt) {
      graphics.lineStyle(4, 0xff0000, 1);
      graphics.strokeRoundedRect(0, 0, size, size, 8);
    }

    graphics.generateTexture(key, size, size);
    graphics.destroy();

    return key;
  }

  destroy(): void {
    if (this.isLocal) {
      this.scene.events.off('update', this.updateLabelPosition, this);
    } else {
      this.scene.events.off('update', this.updateInterpolation, this);
    }
    this.arrow?.destroy();
    this.container.destroy();
    if (this.isLocal) {
      this.sprite.destroy();
    }
  }
}
