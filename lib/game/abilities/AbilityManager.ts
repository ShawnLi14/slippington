import { Ability, AbilityState, AbilitySlot, AbilityContext } from './types';
import { getClass, PlayerClassId } from '../classes';

/**
 * Manages ability cooldowns and execution for a player
 */
export class AbilityManager {
  private states: Map<string, AbilityState> = new Map();
  private classId: PlayerClassId;

  constructor(classId: PlayerClassId) {
    this.classId = classId;
  }

  /**
   * Attempt to use an ability
   * Returns true if ability was activated, false if on cooldown
   */
  useAbility(slot: AbilitySlot, context: AbilityContext): boolean {
    const ability = this.getAbility(slot);
    if (!ability) return false;

    const state = this.states.get(ability.id);
    const now = Date.now();

    // Check cooldown
    if (state && now - state.lastUsed < ability.cooldown) {
      return false;
    }

    // Execute ability
    ability.execute(context);

    // Update state
    const newState: AbilityState = {
      abilityId: ability.id,
      lastUsed: now,
      isActive: !!ability.duration,
      expiresAt: ability.duration ? now + ability.duration : undefined,
    };
    this.states.set(ability.id, newState);

    // Schedule end callback if duration-based
    if (ability.duration && ability.onEnd) {
      setTimeout(() => {
        ability.onEnd!(context);
        const currentState = this.states.get(ability.id);
        if (currentState) {
          currentState.isActive = false;
        }
      }, ability.duration);
    }

    return true;
  }

  /**
   * Get remaining cooldown for an ability (0 if ready)
   */
  getCooldownRemaining(slot: AbilitySlot): number {
    const ability = this.getAbility(slot);
    if (!ability) return 0;

    const state = this.states.get(ability.id);
    if (!state) return 0;

    const elapsed = Date.now() - state.lastUsed;
    return Math.max(0, ability.cooldown - elapsed);
  }

  /**
   * Check if an ability is currently active (for duration-based abilities)
   */
  isAbilityActive(slot: AbilitySlot): boolean {
    const ability = this.getAbility(slot);
    if (!ability) return false;

    const state = this.states.get(ability.id);
    return state?.isActive ?? false;
  }

  /**
   * Get ability definition for a slot
   */
  getAbility(slot: AbilitySlot): Ability | null {
    const playerClass = getClass(this.classId);
    return playerClass.abilities[slot] ?? null;
  }

  /**
   * Reset all cooldowns (e.g., on respawn)
   */
  resetCooldowns(): void {
    this.states.clear();
  }
}

