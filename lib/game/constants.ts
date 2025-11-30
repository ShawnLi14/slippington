// Game configuration constants

export const GAME_CONFIG = {
  // Map dimensions (now 1920x1080)
  MAP_WIDTH: 1920,
  MAP_HEIGHT: 1080,

  // Physics
  GRAVITY: 800,
  JUMP_FORCE: -450,

  // Player settings
  PLAYER_SIZE: 64,
  PLAYER_SPEED: 300,

  // Network settings
  POSITION_UPDATE_INTERVAL: 50, // ms (20 updates/sec max)

  // Game settings
  DEFAULT_GAME_DURATION: 60, // seconds
  TAG_COOLDOWN: 500, // ms (no cooldown for debugging)
} as const;

export const PLAYER_COLORS = [
  '#ff6b6b', '#4ecdc4', '#45b7d1', '#96ceb4',
  '#ffeaa7', '#dfe6e9', '#fd79a8', '#a29bfe',
  '#6c5ce7', '#00b894', '#e17055', '#74b9ff',
] as const;
