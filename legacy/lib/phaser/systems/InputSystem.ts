import * as Phaser from 'phaser';
import { GAME_CONFIG } from '@/lib/game/constants';

/**
 * Input bindings for the game
 */
export interface InputState {
  left: boolean;
  right: boolean;
  jump: boolean;
  down: boolean;
  primaryAbility: boolean;
  secondaryAbility: boolean;
}

/**
 * Handles all keyboard input for the game
 * Separates input reading from game logic
 */
export class InputSystem {
  private cursors!: Phaser.Types.Input.Keyboard.CursorKeys;
  private keys!: {
    W: Phaser.Input.Keyboard.Key;
    A: Phaser.Input.Keyboard.Key;
    S: Phaser.Input.Keyboard.Key;
    D: Phaser.Input.Keyboard.Key;
    Q: Phaser.Input.Keyboard.Key;
    E: Phaser.Input.Keyboard.Key;
    SPACE: Phaser.Input.Keyboard.Key;
  };

  private scene: Phaser.Scene;
  private justPressedKeys: Set<string> = new Set();

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
    this.setup();
  }

  private setup(): void {
    const keyboard = this.scene.input.keyboard!;
    
    this.cursors = keyboard.createCursorKeys();
    this.keys = {
      W: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.W),
      A: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.A),
      S: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.S),
      D: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.D),
      Q: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.Q),
      E: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.E),
      SPACE: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.SPACE),
    };
  }

  /**
   * Get current input state
   */
  getState(): InputState {
    return {
      left: this.cursors.left.isDown || this.keys.A.isDown,
      right: this.cursors.right.isDown || this.keys.D.isDown,
      jump: this.cursors.up.isDown || this.keys.W.isDown || this.keys.SPACE.isDown,
      down: this.cursors.down.isDown || this.keys.S.isDown,
      primaryAbility: Phaser.Input.Keyboard.JustDown(this.keys.Q),
      secondaryAbility: Phaser.Input.Keyboard.JustDown(this.keys.E),
    };
  }

  /**
   * Calculate velocity from input state
   */
  getMovementVelocity(speedMultiplier: number = 1): { x: number; y: number } {
    const state = this.getState();
    let vx = 0;

    if (state.left) vx = -GAME_CONFIG.PLAYER_SPEED * speedMultiplier;
    else if (state.right) vx = GAME_CONFIG.PLAYER_SPEED * speedMultiplier;

    return { x: vx, y: 0 }; // Y handled by physics/jump
  }

  /**
   * Check if jump was just pressed (for single jump trigger)
   */
  isJumpJustPressed(): boolean {
    return (
      Phaser.Input.Keyboard.JustDown(this.cursors.up) ||
      Phaser.Input.Keyboard.JustDown(this.keys.W) ||
      Phaser.Input.Keyboard.JustDown(this.keys.SPACE)
    );
  }

  /**
   * Check if down is pressed (for dropping through platforms)
   */
  isDownPressed(): boolean {
    return this.cursors.down.isDown || this.keys.S.isDown;
  }

  destroy(): void {
    // Keys are automatically cleaned up with the scene
  }
}

