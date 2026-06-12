'use client';

import { useEffect, useRef } from 'react';
import { gameConfig } from '@/lib/phaser/config';

export default function GameCanvas() {
  const gameRef = useRef<Phaser.Game | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Prevent scrolling when game is active
    document.body.style.overflow = 'hidden';
    
    // Only create game once
    if (typeof window !== 'undefined' && !gameRef.current && containerRef.current) {
      import('phaser').then((Phaser) => {
        // Double check we haven't already created the game
        if (gameRef.current) return;
        
        gameRef.current = new Phaser.Game({
          ...gameConfig,
          parent: containerRef.current!,
        });
      });
    }

    return () => {
      // Restore scrolling when game unmounts
      document.body.style.overflow = '';
      
      if (gameRef.current) {
        gameRef.current.destroy(true);
        gameRef.current = null;
      }
    };
  }, []);

  return (
    <div 
      ref={containerRef}
      className="fixed inset-0 bg-[#0f0f1a]"
    />
  );
}
