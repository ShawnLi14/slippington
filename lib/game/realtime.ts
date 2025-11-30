import { supabase } from '@/lib/supabase/client';
import { RealtimeChannel } from '@supabase/supabase-js';
import { Player, Game } from '@/lib/supabase/types';

export type PlayerEventHandler = {
  onPlayerJoin?: (player: Player) => void;
  onPlayerUpdate?: (player: Player) => void;
  onPlayerLeave?: (playerId: string) => void;
  onGameUpdate?: (game: Game) => void;
};

/**
 * Manages realtime subscriptions for a game
 */
export class GameRealtimeChannel {
  private channel: RealtimeChannel | null = null;
  private gameId: string;
  private handlers: PlayerEventHandler;

  constructor(gameId: string, handlers: PlayerEventHandler) {
    this.gameId = gameId;
    this.handlers = handlers;
  }

  subscribe(): void {
    this.channel = supabase
      .channel(`game-${this.gameId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'players',
          filter: `game_id=eq.${this.gameId}`,
        },
        (payload) => {
          this.handlers.onPlayerJoin?.(payload.new as Player);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'players',
          filter: `game_id=eq.${this.gameId}`,
        },
        (payload) => {
          this.handlers.onPlayerUpdate?.(payload.new as Player);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'DELETE',
          schema: 'public',
          table: 'players',
          filter: `game_id=eq.${this.gameId}`,
        },
        (payload) => {
          const player = payload.old as { id: string };
          this.handlers.onPlayerLeave?.(player.id);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'games',
          filter: `id=eq.${this.gameId}`,
        },
        (payload) => {
          this.handlers.onGameUpdate?.(payload.new as Game);
        }
      )
      .subscribe();
  }

  async unsubscribe(): Promise<void> {
    if (this.channel) {
      await supabase.removeChannel(this.channel);
      this.channel = null;
    }
  }
}

