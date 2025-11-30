'use client';

import { useState, useEffect } from 'react';
import { getAllClasses, PlayerClass, PlayerClassId } from '@/lib/game/classes';
import { GamesService, GameWithPlayerCount } from '@/lib/supabase/games';
import { useGameStore } from '@/lib/game/state';

interface MainMenuProps {
  onStartGame: () => void;
}

export default function MainMenu({ onStartGame }: MainMenuProps) {
  const [selectedClassId, setSelectedClassId] = useState<PlayerClassId>('speedster');
  const [selectedGameId, setSelectedGameId] = useState<string | null>(null);
  const [games, setGames] = useState<GameWithPlayerCount[]>([]);
  const [loading, setLoading] = useState(false);
  const classes = getAllClasses();

  useEffect(() => {
    refreshGames();
    const interval = setInterval(refreshGames, 5000);
    return () => clearInterval(interval);
  }, []);

  async function refreshGames() {
    try {
      const data = await GamesService.getAllWaiting();
      setGames(data);
    } catch (error) {
      console.error('Failed to fetch games:', error);
    }
  }

  function handleStartGame(joinGameId: string | null) {
    setLoading(true);
    useGameStore.getState().setSelectedClass(selectedClassId);
    if (joinGameId) {
      useGameStore.getState().setGameId(joinGameId);
    }
    onStartGame();
  }

  const classColors: Record<string, string> = {
    speedster: '#4ecdc4',
    tank: '#ff6b6b',
    trickster: '#a29bfe',
  };

  return (
    <div className="min-h-screen bg-[#0a0a12] text-white flex flex-col">
      {/* Background grid */}
      <div 
        className="fixed inset-0 opacity-10 pointer-events-none"
        style={{
          backgroundImage: 'linear-gradient(#1a1a2e 1px, transparent 1px), linear-gradient(90deg, #1a1a2e 1px, transparent 1px)',
          backgroundSize: '40px 40px',
        }}
      />
      
      {/* Accent glow */}
      <div className="fixed top-0 left-0 right-0 h-40 bg-gradient-to-b from-[#4ecdc4]/10 to-transparent pointer-events-none" />

      {/* Header */}
      <header className="relative z-10 text-center pt-12 pb-8">
        <h1 className="text-5xl font-bold tracking-tight">SLIPPINGTON</h1>
        <p className="text-[#4ecdc4] text-sm tracking-[0.3em] mt-2">MULTIPLAYER TAG</p>
      </header>

      {/* Main content */}
      <main className="relative z-10 flex-1 flex gap-8 px-8 pb-8 max-w-6xl mx-auto w-full">
        {/* Left: Class Selection */}
        <section className="w-80 flex-shrink-0">
          <div className="bg-[#12121f] border border-[#2a2a4a] rounded-lg p-6">
            <h2 className="text-[#4ecdc4] text-xs tracking-[0.2em] mb-6">SELECT CLASS</h2>
            
            <div className="space-y-4">
              {classes.map((playerClass) => (
                <ClassCard
                  key={playerClass.id}
                  playerClass={playerClass}
                  isSelected={selectedClassId === playerClass.id}
                  color={classColors[playerClass.id] || '#4ecdc4'}
                  onClick={() => setSelectedClassId(playerClass.id as PlayerClassId)}
                />
              ))}
            </div>
          </div>
        </section>

        {/* Right: Game Browser */}
        <section className="flex-1 flex flex-col">
          <div className="bg-[#12121f] border border-[#2a2a4a] rounded-lg p-6 flex-1 flex flex-col">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-[#4ecdc4] text-xs tracking-[0.2em]">AVAILABLE GAMES</h2>
              <button 
                onClick={refreshGames}
                className="text-xs text-gray-500 hover:text-white transition-colors"
              >
                ↻ REFRESH
              </button>
            </div>

            <div className="flex-1 overflow-y-auto space-y-3 min-h-[200px]">
              {games.length === 0 ? (
                <div className="text-center text-gray-500 py-12">
                  <p>No games available</p>
                  <p className="text-sm mt-1">Create one to get started!</p>
                </div>
              ) : (
                games.map((game) => (
                  <GameCard
                    key={game.id}
                    game={game}
                    isSelected={selectedGameId === game.id}
                    onClick={() => setSelectedGameId(game.id)}
                  />
                ))
              )}
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex gap-4 mt-6">
            <button
              onClick={() => handleStartGame(null)}
              disabled={loading}
              className="flex-1 bg-[#4ecdc4] hover:bg-[#5eddd4] text-[#0a0a12] font-bold py-4 rounded-lg transition-colors disabled:opacity-50"
            >
              {loading ? 'STARTING...' : 'CREATE GAME'}
            </button>
            <button
              onClick={() => handleStartGame(selectedGameId)}
              disabled={loading || !selectedGameId}
              className="flex-1 bg-transparent border-2 border-[#4ecdc4] text-[#4ecdc4] hover:bg-[#4ecdc4]/10 font-bold py-4 rounded-lg transition-colors disabled:opacity-50 disabled:border-gray-600 disabled:text-gray-600"
            >
              JOIN GAME
            </button>
          </div>
        </section>
      </main>
    </div>
  );
}

function ClassCard({ 
  playerClass, 
  isSelected, 
  color, 
  onClick 
}: { 
  playerClass: PlayerClass; 
  isSelected: boolean; 
  color: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`w-full text-left p-4 rounded-lg border-2 transition-all ${
        isSelected 
          ? 'bg-[#1a1a2e] border-current' 
          : 'bg-[#0f0f1a] border-[#2a2a4a] hover:bg-[#1a1a2e]'
      }`}
      style={{ borderColor: isSelected ? color : undefined }}
    >
      <div className="flex items-start gap-4">
        {/* Class icon */}
        <div 
          className="w-12 h-12 rounded-lg flex-shrink-0"
          style={{ backgroundColor: color }}
        />
        
        <div className="flex-1 min-w-0">
          <h3 className="font-bold text-sm">{playerClass.name.toUpperCase()}</h3>
          <p className="text-xs text-gray-400 mt-1 line-clamp-2">{playerClass.description}</p>
          
          {/* Stats */}
          <div className="flex gap-4 mt-3">
            <StatBar label="SPD" value={playerClass.stats.speed} color={color} />
            <StatBar label="JMP" value={playerClass.stats.jumpForce} color={color} />
          </div>
        </div>
      </div>
    </button>
  );
}

function StatBar({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[10px] text-gray-500 w-6">{label}</span>
      <div className="w-12 h-1.5 bg-[#0a0a12] rounded-full overflow-hidden">
        <div 
          className="h-full rounded-full transition-all"
          style={{ 
            width: `${Math.min(value / 1.5, 1) * 100}%`,
            backgroundColor: color,
          }}
        />
      </div>
    </div>
  );
}

function GameCard({ 
  game, 
  isSelected, 
  onClick 
}: { 
  game: GameWithPlayerCount; 
  isSelected: boolean; 
  onClick: () => void;
}) {
  const maxPlayers = game.settings?.maxPlayers || 8;
  const isFull = game.playerCount >= maxPlayers;

  return (
    <button
      onClick={onClick}
      disabled={isFull}
      className={`w-full text-left p-4 rounded-lg border-2 transition-all ${
        isSelected 
          ? 'bg-[#1a1a2e] border-[#4ecdc4]' 
          : 'bg-[#0f0f1a] border-[#2a2a4a] hover:bg-[#1a1a2e]'
      } ${isFull ? 'opacity-50 cursor-not-allowed' : ''}`}
    >
      <div className="flex items-center justify-between">
        <div>
          <h3 className="font-bold text-sm">GAME {game.id.slice(0, 8).toUpperCase()}</h3>
          <p className="text-xs text-gray-400 mt-1">
            {game.playerCount}/{maxPlayers} players
          </p>
        </div>
        <div 
          className={`w-3 h-3 rounded-full ${isFull ? 'bg-red-500' : 'bg-[#4ecdc4]'}`}
        />
      </div>
    </button>
  );
}

