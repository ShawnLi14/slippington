import * as Phaser from 'phaser';

/**
 * Animation states for player characters
 */
export type AnimationState = 
  | 'idle'
  | 'run'
  | 'jump'
  | 'fall'
  | 'land'
  | 'ability_primary'
  | 'ability_secondary';

/**
 * Animation configuration for a sprite sheet
 */
export interface AnimationConfig {
  key: string;
  frames: { start: number; end: number };
  frameRate: number;
  repeat: number; // -1 for loop
}

/**
 * Full animation set for a character class
 */
export interface CharacterAnimations {
  spriteSheet: string;
  frameWidth: number;
  frameHeight: number;
  animations: Record<AnimationState, AnimationConfig>;
}

/**
 * Manages animation state and transitions for a sprite
 */
export class AnimationSystem {
  private scene: Phaser.Scene;
  private sprite: Phaser.GameObjects.Sprite;
  private currentState: AnimationState = 'idle';
  private locked: boolean = false; // For non-interruptible animations
  private spriteKey: string;

  constructor(scene: Phaser.Scene, sprite: Phaser.GameObjects.Sprite, spriteKey: string) {
    this.scene = scene;
    this.sprite = sprite;
    this.spriteKey = spriteKey;
  }

  /**
   * Update animation based on physics state
   */
  update(velocityX: number, velocityY: number, onGround: boolean): void {
    if (this.locked) return;

    let newState: AnimationState;

    if (!onGround) {
      newState = velocityY < 0 ? 'jump' : 'fall';
    } else if (Math.abs(velocityX) > 10) {
      newState = 'run';
    } else {
      newState = 'idle';
    }

    this.setState(newState);

    // Flip sprite based on direction
    if (velocityX < 0) {
      this.sprite.setFlipX(true);
    } else if (velocityX > 0) {
      this.sprite.setFlipX(false);
    }
  }

  /**
   * Set animation state (only changes if different)
   */
  setState(state: AnimationState): void {
    if (state === this.currentState) return;

    this.currentState = state;
    const animKey = `${this.spriteKey}_${state}`;
    
    if (this.scene.anims.exists(animKey)) {
      this.sprite.play(animKey);
    }
  }

  /**
   * Play a one-shot animation that can't be interrupted
   */
  playOnce(state: AnimationState, onComplete?: () => void): void {
    this.locked = true;
    this.currentState = state;
    
    const animKey = `${this.spriteKey}_${state}`;
    
    if (this.scene.anims.exists(animKey)) {
      this.sprite.play(animKey);
      this.sprite.once('animationcomplete', () => {
        this.locked = false;
        onComplete?.();
      });
    } else {
      this.locked = false;
      onComplete?.();
    }
  }

  /**
   * Get current animation state
   */
  getState(): AnimationState {
    return this.currentState;
  }

  /**
   * Check if facing right
   */
  isFacingRight(): boolean {
    return !this.sprite.flipX;
  }
}

/**
 * Register animations for a character class
 */
export function registerCharacterAnimations(
  scene: Phaser.Scene,
  config: CharacterAnimations
): void {
  for (const [state, animConfig] of Object.entries(config.animations)) {
    const key = `${config.spriteSheet}_${state}`;
    
    if (!scene.anims.exists(key)) {
      scene.anims.create({
        key,
        frames: scene.anims.generateFrameNumbers(config.spriteSheet, {
          start: animConfig.frames.start,
          end: animConfig.frames.end,
        }),
        frameRate: animConfig.frameRate,
        repeat: animConfig.repeat,
      });
    }
  }
}

