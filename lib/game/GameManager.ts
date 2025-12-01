import { GamesService } from '@/lib/supabase/games';
import { PlayersService } from '@/lib/supabase/players';
import { GameRealtimeChannel, PlayerEventHandler } from './realtime';
import { getUserId } from './session';
import { useGameStore } from './state';
import { GAME_CONFIG } from './constants';
import { Player as DbPlayer } from '@/lib/supabase/types';
import { Player } from './types';
import { PlayerClassId } from './classes';
import { MapGenerator, MapData } from './maps';

/**
 * High-level game manager that coordinates all game operations
 */
export class GameManager {
  private realtimeChannel: GameRealtimeChannel | null = null;
  private positionUpdateTimer: number = 0;
  private currentMapData: MapData | null = null;
  private currentGameId: string | null = null;

  /**
   * Join an existing game or create a new one
   * @param existingGameId - If provided, join this specific game. Otherwise create new.
   */
  async joinOrCreateGame(existingGameId?: string | null): Promise<{ gameId: string; playerId: string; mapData: MapData }> {
    const userId = getUserId();
    const store = useGameStore.getState();
    const selectedClass = (store.selectedClass as PlayerClassId) || 'slipper';

    let game;
    let isFirstPlayer = false;

    if (existingGameId) {
      // Join specific game
      game = await GamesService.getById(existingGameId);
      if (!game) {
        throw new Error('Game not found');
      }
      // Check if there are existing players
      const existingPlayers = await PlayersService.getByGameId(existingGameId);
      isFirstPlayer = existingPlayers.length === 0;
    } else {
      // Create new game - creator is always first
      game = await GamesService.create();
      isFirstPlayer = true;
    }

    this.currentGameId = game.id;

    // Generate map from seed
    const mapSeed = game.map_seed || MapGenerator.generateSeed();
    const mapGenerator = new MapGenerator(mapSeed);
    const mapData = mapGenerator.generate();
    this.currentMapData = mapData;

    // Pick a spawn point
    const spawnIndex = Math.floor(Math.random() * mapData.spawnPoints.length);
    const spawn = mapData.spawnPoints[spawnIndex];

    // Create player (first player starts as "it")
    const player = await PlayersService.create({
      gameId: game.id,
      userId,
      classId: selectedClass,
      spawnX: spawn.x,
      spawnY: spawn.y,
      isFirstPlayer,
    });

    // Update store
    store.setGameId(game.id);
    store.setLocalPlayerId(player.id);
    store.setMapSeed(mapSeed);
    store.addPlayer(this.toGamePlayer(player));

    return { gameId: game.id, playerId: player.id, mapData };
  }

  async subscribeToGame(gameId: string): Promise<void> {
    const store = useGameStore.getState();

    // Fetch existing players
    const players = await PlayersService.getByGameId(gameId);
    const playersMap: Record<string, Player> = {};
    players.forEach((p) => {
      playersMap[p.id] = this.toGamePlayer(p);
    });
    store.setPlayers(playersMap);

    // Set up realtime handlers
    const handlers: PlayerEventHandler = {
      onPlayerJoin: (player) => {
        useGameStore.getState().addPlayer(this.toGamePlayer(player));
      },
      onPlayerUpdate: (player) => {
        useGameStore.getState().updatePlayer(player.id, this.toGamePlayer(player));
      },
      onPlayerLeave: (playerId) => {
        useGameStore.getState().removePlayer(playerId);
      },
      onGameUpdate: (game) => {
        useGameStore.getState().setStatus(game.status);
        useGameStore.getState().setTimerEnd(game.timer_end);
      },
    };

    this.realtimeChannel = new GameRealtimeChannel(gameId, handlers);
    this.realtimeChannel.subscribe();
  }

  updatePosition(playerId: string, x: number, y: number, velocityY: number = 0, facingRight: boolean = true): void {
    const now = Date.now();
    if (now - this.positionUpdateTimer < GAME_CONFIG.POSITION_UPDATE_INTERVAL) {
      return;
    }
    this.positionUpdateTimer = now;
    PlayersService.updatePosition(playerId, x, y, velocityY, facingRight);
  }

  async leaveGame(playerId: string): Promise<void> {
    await PlayersService.delete(playerId);
    await this.realtimeChannel?.unsubscribe();
    this.realtimeChannel = null;
    this.currentMapData = null;
    this.currentGameId = null;
    useGameStore.getState().reset();
  }

  /**
   * Attempt to tag another player. Returns true if successful.
   * Uses atomic transfer to prevent race conditions.
   */
  async tagPlayer(taggerId: string, taggedId: string): Promise<boolean> {
    if (!this.currentGameId) return false;
    return await PlayersService.transferTag(taggerId, taggedId, this.currentGameId);
  }

  async setPlayerIsIt(playerId: string, isIt: boolean): Promise<void> {
    await PlayersService.setIsIt(playerId, isIt);
  }

  async startGame(gameId: string, durationSeconds: number = GAME_CONFIG.DEFAULT_GAME_DURATION): Promise<void> {
    const timerEnd = new Date(Date.now() + durationSeconds * 1000).toISOString();
    await GamesService.setTimerEnd(gameId, timerEnd);
  }

  getMapData(): MapData | null {
    return this.currentMapData;
  }

  private toGamePlayer(dbPlayer: DbPlayer): Player {
    return {
      id: dbPlayer.id,
      game_id: dbPlayer.game_id,
      user_id: dbPlayer.user_id,
      x: dbPlayer.x,
      y: dbPlayer.y,
      velocity_y: dbPlayer.velocity_y,
      is_it: dbPlayer.is_it,
      color: dbPlayer.color,
      class_id: dbPlayer.class_id as PlayerClassId,
      facing_right: dbPlayer.facing_right,
    };
  }
}

// Singleton instance
export const gameManager = new GameManager();
