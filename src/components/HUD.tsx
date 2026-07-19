import React from 'react'
import { useGameStore } from '../store/gameStore'

export function HUD() {
  const isLoading = useGameStore((state) => state.isLoading)
  const progress = useGameStore((state) => state.loadingProgress)
  const isSolved = useGameStore((state) => state.isSolved)

  if (isLoading) {
    return (
      <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black text-white font-mono pointer-events-auto">
        <div className="text-2xl tracking-[0.3em] font-light mb-8 text-white/80">INITIALIZING NEURAL LINK</div>
        <div className="w-64 h-1 bg-white/10 rounded-full overflow-hidden">
          <div 
            className="h-full bg-white/80 transition-all duration-300 ease-out"
            style={{ width: `${progress}%` }}
          />
        </div>
        <div className="mt-4 text-xs text-white/40 tracking-widest">
          SYS.LOAD {progress}%
        </div>
      </div>
    )
  }

  return (
    <div className="absolute inset-0 pointer-events-none z-40 p-8 font-mono">
      {/* Top Left Objective */}
      <div className="flex flex-col gap-2 opacity-80">
        <div className="text-xs text-white/50 tracking-widest">CURRENT DIRECTIVE</div>
        <div className={`text-sm tracking-[0.2em] ${isSolved ? 'text-green-400' : 'text-white'}`}>
          {isSolved ? '> ARTIFACT SECURED' : '> ALIGN THE ARTIFACT RINGS'}
        </div>
      </div>

      {/* Crosshair Brackets (Cinematic) */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[400px] h-[300px] opacity-20">
        {/* Top Left Bracket */}
        <div className="absolute top-0 left-0 w-8 h-8 border-t-2 border-l-2 border-white" />
        {/* Top Right Bracket */}
        <div className="absolute top-0 right-0 w-8 h-8 border-t-2 border-r-2 border-white" />
        {/* Bottom Left Bracket */}
        <div className="absolute bottom-0 left-0 w-8 h-8 border-b-2 border-l-2 border-white" />
        {/* Bottom Right Bracket */}
        <div className="absolute bottom-0 right-0 w-8 h-8 border-b-2 border-r-2 border-white" />
      </div>

      {/* Bottom Right System Status */}
      <div className="absolute bottom-8 right-8 text-right opacity-60">
        <div className="text-xs text-white tracking-widest mb-1">SYS.ONLINE</div>
        <div className="text-[10px] text-white/50 tracking-widest">
          MEM_ALLOC: 4.2GB
          <br />
          GPU: PATH_TRACING_ACTIVE
        </div>
      </div>

      {/* Bottom Left Controls Guide */}
      <div className="absolute bottom-8 left-8 opacity-60 flex flex-col gap-1">
        <div className="text-[10px] text-white/50 tracking-widest uppercase">Controls</div>
        <div className="text-xs text-white tracking-widest">
          [CLICK] LOCK INTERFACE
          <br />
          [W,A,S,D] TRAVERSE
          <br />
          [SCROLL] ROTATE RINGS
          <br />
          [ESC] UNLOCK
        </div>
      </div>
    </div>
  )
}
