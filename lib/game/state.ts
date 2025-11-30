import { create } from 'zustand';
import { GameState, Player } from './types';

interface GameStore extends GameState {
  // Connection actions
  setGameId: (gameId: string) => void;
  setLocalPlayerId: (playerId: string) => void;
  setSelectedClass: (classId: string) => void;
  
  // Game state actions
  setStatus: (status: GameState['status']) => void;
  setTimerEnd: (timerEnd: string | null) => void;
  setMapSeed: (seed: string) => void;
  
  // Player actions
  addPlayer: (player: Player) => void;
  updatePlayer: (playerId: string, updates: Partial<Player>) => void;
  removePlayer: (playerId: string) => void;
  setPlayers: (players: Record<string, Player>) => void;
  
  // Utility
  reset: () => void;
  getLocalPlayer: () => Player | null;
}

const initialState: GameState = {
  gameId: null,
  localPlayerId: null,
  selectedClass: null,
  players: {},
  status: 'loading',
  timerEnd: null,
  mapSeed: null,
};

export const useGameStore = create<GameStore>((set, get) => ({
  ...initialState,

  // Connection actions
  setGameId: (gameId) => set({ gameId }),
  setLocalPlayerId: (localPlayerId) => set({ localPlayerId }),
  setSelectedClass: (selectedClass) => set({ selectedClass }),

  // Game state actions
  setStatus: (status) => set({ status }),
  setTimerEnd: (timerEnd) => set({ timerEnd }),
  setMapSeed: (mapSeed) => set({ mapSeed }),

  // Player actions
  addPlayer: (player) =>
    set((state) => ({
      players: { ...state.players, [player.id]: player },
    })),

  updatePlayer: (playerId, updates) =>
    set((state) => {
      const existing = state.players[playerId];
      if (!existing) return state;
      return {
        players: {
          ...state.players,
          [playerId]: { ...existing, ...updates },
        },
      };
    }),

  removePlayer: (playerId) =>
    set((state) => {
      const { [playerId]: _, ...rest } = state.players;
      return { players: rest };
    }),

  setPlayers: (players) => set({ players }),

  // Utility
  reset: () => set(initialState),
  
  getLocalPlayer: () => {
    const state = get();
    if (!state.localPlayerId) return null;
    return state.players[state.localPlayerId] ?? null;
  },
}));
