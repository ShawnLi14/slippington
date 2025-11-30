import { supabase } from './client';
import { Player } from './types';
import { PLAYER_COLORS, GAME_CONFIG } from '@/lib/game/constants';
import { PlayerClassId } from '@/lib/game/classes';

export interface CreatePlayerOptions {
  gameId: string;
  userId: string;
  classId?: PlayerClassId;
  spawnX?: number;
  spawnY?: number;
  isFirstPlayer?: boolean;
}

type PlayerInsert = {
  game_id: string;
  user_id: string;
  x?: number;
  y?: number;
  velocity_y?: number;
  is_it?: boolean;
  color?: string;
  class_id?: string;
  facing_right?: boolean;
};

/**
 * Player database operations
 */
export const PlayersService = {
  async getByGameId(gameId: string): Promise<Player[]> {
    const { data, error } = await supabase
      .from('players')
      .select('*')
      .eq('game_id', gameId);

    if (error) {
      throw new Error(`Failed to fetch players: ${error.message}`);
    }
    return (data || []) as Player[];
  },

  async create(options: CreatePlayerOptions): Promise<Player> {
    const { gameId, userId, classId = 'speedster', spawnX, spawnY, isFirstPlayer = false } = options;
    
    const insertData: PlayerInsert = {
      game_id: gameId,
      user_id: userId,
      x: Math.round(spawnX ?? GAME_CONFIG.MAP_WIDTH / 2),
      y: Math.round(spawnY ?? GAME_CONFIG.MAP_HEIGHT - 100),
      velocity_y: 0,
      is_it: isFirstPlayer, // First player starts as "it"
      color: PLAYER_COLORS[Math.floor(Math.random() * PLAYER_COLORS.length)],
      class_id: classId,
      facing_right: true,
    };

    const { data, error } = await supabase
      .from('players')
      .insert(insertData as never)
      .select()
      .single();

    if (error || !data) {
      throw new Error(`Failed to create player: ${error?.message}`);
    }
    return data as Player;
  },

  async updatePosition(playerId: string, x: number, y: number, velocityY: number = 0, facingRight: boolean = true): Promise<void> {
    await supabase
      .from('players')
      .update({ 
        x: Math.round(x), 
        y: Math.round(y),
        velocity_y: Math.round(velocityY),
        facing_right: facingRight,
      } as never)
      .eq('id', playerId);
  },

  async setIsIt(playerId: string, isIt: boolean): Promise<void> {
    const { error } = await supabase
      .from('players')
      .update({ is_it: isIt } as never)
      .eq('id', playerId);

    if (error) {
      throw new Error(`Failed to update is_it: ${error.message}`);
    }
  },

  /**
   * Atomically transfer "it" status from one player to another.
   * Only succeeds if the tagger is currently "it".
   * This prevents race conditions where both players try to tag each other.
   */
  async transferTag(taggerId: string, taggedId: string, gameId: string): Promise<boolean> {
    // First, verify the tagger is actually "it" (prevents double-tags)
    const { data: tagger } = await supabase
      .from('players')
      .select('is_it')
      .eq('id', taggerId)
      .single();

    const taggerData = tagger as { is_it: boolean } | null;
    if (!taggerData?.is_it) {
      return false;
    }

    // Clear all "it" status for this game first, then set the new "it"
    await supabase
      .from('players')
      .update({ is_it: false } as never)
      .eq('game_id', gameId);

    const { error } = await supabase
      .from('players')
      .update({ is_it: true } as never)
      .eq('id', taggedId);

    if (error) {
      throw new Error(`Failed to transfer tag: ${error.message}`);
    }

    return true;
  },

  async updateClass(playerId: string, classId: PlayerClassId): Promise<void> {
    const { error } = await supabase
      .from('players')
      .update({ class_id: classId } as never)
      .eq('id', playerId);

    if (error) {
      throw new Error(`Failed to update class: ${error.message}`);
    }
  },

  async delete(playerId: string): Promise<void> {
    await supabase.from('players').delete().eq('id', playerId);
  },
};
