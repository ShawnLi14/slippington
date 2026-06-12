import { supabase } from './client';
import { Game, GameSettings } from './types';
import { MapGenerator } from '@/lib/game/maps';

type GameInsert = {
  status?: 'waiting' | 'playing' | 'finished';
  timer_end?: string | null;
  map_seed?: string | null;
  settings?: GameSettings | null;
};

export interface GameWithPlayerCount extends Game {
  playerCount: number;
}

/**
 * Game database operations
 */
export const GamesService = {
  async findWaiting(): Promise<Game | null> {
    const { data } = await supabase
      .from('games')
      .select('*')
      .eq('status', 'waiting')
      .limit(1)
      .single();
    return data as Game | null;
  },

  async getAllWaiting(): Promise<GameWithPlayerCount[]> {
    const { data: games } = await supabase
      .from('games')
      .select('*')
      .eq('status', 'waiting')
      .order('created_at', { ascending: false });

    if (!games || games.length === 0) return [];

    // Get player counts for each game
    const gamesWithCounts: GameWithPlayerCount[] = [];
    
    for (const game of games as Game[]) {
      const { count } = await supabase
        .from('players')
        .select('*', { count: 'exact', head: true })
        .eq('game_id', game.id);
      
      gamesWithCounts.push({
        ...game,
        playerCount: count || 0,
      });
    }

    return gamesWithCounts;
  },

  async create(settings?: Partial<GameSettings>): Promise<Game> {
    const mapSeed = MapGenerator.generateSeed();
    const defaultSettings: GameSettings = {
      duration: 60,
      maxPlayers: 8,
      ...settings,
    };

    const insertData: GameInsert = {
      status: 'waiting',
      map_seed: mapSeed,
      settings: defaultSettings,
    };

    const { data, error } = await supabase
      .from('games')
      .insert(insertData as never)
      .select()
      .single();

    if (error || !data) {
      throw new Error(`Failed to create game: ${error?.message}`);
    }
    return data as Game;
  },

  async getById(gameId: string): Promise<Game | null> {
    const { data } = await supabase
      .from('games')
      .select('*')
      .eq('id', gameId)
      .single();
    return data as Game | null;
  },

  async updateStatus(gameId: string, status: Game['status']): Promise<void> {
    const { error } = await supabase
      .from('games')
      .update({ status } as never)
      .eq('id', gameId);

    if (error) {
      throw new Error(`Failed to update game status: ${error.message}`);
    }
  },

  async setTimerEnd(gameId: string, timerEnd: string): Promise<void> {
    const { error } = await supabase
      .from('games')
      .update({ timer_end: timerEnd, status: 'playing' } as never)
      .eq('id', gameId);

    if (error) {
      throw new Error(`Failed to set timer: ${error.message}`);
    }
  },
};
