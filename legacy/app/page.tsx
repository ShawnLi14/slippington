'use client';

import { useState } from 'react';
import dynamic from 'next/dynamic';
import MainMenu from '@/components/MainMenu';

const GameCanvas = dynamic(() => import('@/components/GameCanvas'), { ssr: false });

export default function Home() {
  const [gameStarted, setGameStarted] = useState(false);

  if (!gameStarted) {
    return <MainMenu onStartGame={() => setGameStarted(true)} />;
  }

  return <GameCanvas />;
}
