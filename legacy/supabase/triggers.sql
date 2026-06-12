-- Triggers for automatic game cleanup
-- Run this in Supabase SQL Editor after schema.sql

-- ===========================================
-- AUTO-CLEANUP: End games with no players
-- ===========================================

-- Function to check if a game is empty and mark it as finished
CREATE OR REPLACE FUNCTION check_empty_game()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if the game has no players left
  IF NOT EXISTS (
    SELECT 1 FROM players WHERE game_id = OLD.game_id
  ) THEN
    -- Mark game as finished
    UPDATE games SET status = 'finished' WHERE id = OLD.game_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger: When a player is deleted, check if game should end
DROP TRIGGER IF EXISTS on_player_leave ON players;
CREATE TRIGGER on_player_leave
AFTER DELETE ON players
FOR EACH ROW
EXECUTE FUNCTION check_empty_game();

-- ===========================================
-- CLEANUP: Remove old finished games (optional)
-- Run manually or via cron to clean up old data
-- ===========================================

-- Function to delete games finished more than 1 hour ago
CREATE OR REPLACE FUNCTION cleanup_old_games()
RETURNS void AS $$
BEGIN
  DELETE FROM games 
  WHERE status = 'finished' 
  AND created_at < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

