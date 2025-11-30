-- Complete database schema for multiplayer tag game
-- This file represents the current state of the database

-- ===========================================
-- EXTENSIONS
-- ===========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ===========================================
-- TABLES
-- ===========================================

-- Games: Represents a game session
CREATE TABLE games (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  status TEXT DEFAULT 'waiting' CHECK (status IN ('waiting', 'playing', 'finished')),
  timer_end TIMESTAMPTZ,
  map_seed TEXT,
  settings JSONB DEFAULT '{"duration": 60, "maxPlayers": 8}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Players: Represents players in a game
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  game_id UUID REFERENCES games(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  is_it BOOLEAN DEFAULT FALSE,
  x INTEGER DEFAULT 400,
  y INTEGER DEFAULT 300,
  velocity_y INTEGER DEFAULT 0,
  color TEXT DEFAULT '#96ceb4',
  class_id TEXT DEFAULT 'speedster',
  facing_right BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ability Events: Track ability usage for replay/validation
CREATE TABLE ability_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  game_id UUID REFERENCES games(id) ON DELETE CASCADE,
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  ability_id TEXT NOT NULL,
  triggered_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===========================================
-- INDEXES
-- ===========================================
CREATE INDEX idx_players_game_id ON players(game_id);
CREATE INDEX idx_games_status ON games(status);
CREATE INDEX idx_ability_events_game_id ON ability_events(game_id);

-- ===========================================
-- REALTIME
-- ===========================================
-- Enable realtime subscriptions for game state sync
ALTER PUBLICATION supabase_realtime ADD TABLE games;
ALTER PUBLICATION supabase_realtime ADD TABLE players;
ALTER PUBLICATION supabase_realtime ADD TABLE ability_events;
