export interface Database {
  public: {
    Tables: {
      games: {
        Row: {
          id: string;
          status: 'waiting' | 'playing' | 'finished';
          timer_end: string | null;
          map_seed: string | null;
          settings: GameSettings | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          status?: 'waiting' | 'playing' | 'finished';
          timer_end?: string | null;
          map_seed?: string | null;
          settings?: GameSettings | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          status?: 'waiting' | 'playing' | 'finished';
          timer_end?: string | null;
          map_seed?: string | null;
          settings?: GameSettings | null;
          created_at?: string;
        };
      };
      players: {
        Row: {
          id: string;
          game_id: string | null;
          user_id: string;
          is_it: boolean;
          x: number;
          y: number;
          velocity_y: number;
          color: string;
          class_id: string;
          facing_right: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          game_id?: string | null;
          user_id: string;
          is_it?: boolean;
          x?: number;
          y?: number;
          velocity_y?: number;
          color?: string;
          class_id?: string;
          facing_right?: boolean;
          created_at?: string;
        };
        Update: {
          id?: string;
          game_id?: string | null;
          user_id?: string;
          is_it?: boolean;
          x?: number;
          y?: number;
          velocity_y?: number;
          color?: string;
          class_id?: string;
          facing_right?: boolean;
          created_at?: string;
        };
      };
      ability_events: {
        Row: {
          id: string;
          game_id: string;
          player_id: string;
          ability_id: string;
          triggered_at: string;
        };
        Insert: {
          id?: string;
          game_id: string;
          player_id: string;
          ability_id: string;
          triggered_at?: string;
        };
        Update: {
          id?: string;
          game_id?: string;
          player_id?: string;
          ability_id?: string;
          triggered_at?: string;
        };
      };
    };
  };
}

export interface GameSettings {
  duration: number;
  mapPreset?: string;
  maxPlayers: number;
}

export type Game = Database['public']['Tables']['games']['Row'];
export type Player = Database['public']['Tables']['players']['Row'];
export type AbilityEvent = Database['public']['Tables']['ability_events']['Row'];
