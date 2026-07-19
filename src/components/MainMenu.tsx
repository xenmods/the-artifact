import { useEffect, useRef, useState } from "react";
import { useGameStore } from "../store/gameStore";

export function MainMenu() {
  const setScreen = useGameStore((s) => s.setScreen);
  const isLoading = useGameStore((s) => s.isLoading);
  const hasPlayed = useGameStore((s) => s.hasPlayed);
  const setHasPlayed = useGameStore((s) => s.setHasPlayed);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!containerRef.current) return;
      const x = (e.clientX / window.innerWidth - 0.5) * 10;
      const y = (e.clientY / window.innerHeight - 0.5) * 10;
      containerRef.current.style.transform = `perspective(1000px) rotateX(${-y}deg) rotateY(${x}deg)`;
    };
    window.addEventListener("mousemove", handleMouseMove);
    return () => window.removeEventListener("mousemove", handleMouseMove);
  }, []);

  const [showSettings, setShowSettings] = useState(false);
  const settings = useGameStore((s) => s.settings);
  const updateSettings = useGameStore((s) => s.updateSettings);

  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center z-40 bg-black/40 backdrop-blur-md font-mono text-white pointer-events-auto">
      {/* Top Right Settings Button */}
      <button
        onClick={() => setShowSettings(!showSettings)}
        className="absolute top-8 right-8 text-xs tracking-widest text-white/50 hover:text-white transition-colors"
      >
        [ {showSettings ? "CLOSE" : "SETTINGS"} ]
      </button>

      <div
        ref={containerRef}
        className="flex flex-col items-center transition-transform duration-200 ease-out w-full max-w-2xl"
        style={{ transformStyle: "preserve-3d" }}
      >
        {!showSettings ? (
          <>
            <div className="text-xs text-white/50 tracking-widest mb-4">
              SYS.LOGIN_SEQUENCE
            </div>

            <h1
              className="text-5xl font-light tracking-[0.4em] mb-2 text-white/90"
              style={{ textShadow: "0 0 20px rgba(255,255,255,0.3)" }}
            >
              THE ARTIFACT
            </h1>

            <div
              className="text-sm text-white/40 tracking-[0.2em] uppercase"
              style={{ marginBottom: "64px" }}
            >
              Neural Interface v2.0
            </div>

            <button
              onClick={() => {
                if (!isLoading) {
                  setScreen("game");
                  setHasPlayed(true);
                }
              }}
              disabled={isLoading}
              className="group relative border border-white/20 hover:border-white/80 transition-all duration-300 disabled:opacity-50 disabled:cursor-not-allowed bg-black/50"
              style={{ padding: "4px 12px" }}
            >
              {/* Brackets */}
              <div className="absolute top-0 left-0 w-2 h-2 border-t border-l border-white/50 group-hover:border-white transition-colors" />
              <div className="absolute top-0 right-0 w-2 h-2 border-t border-r border-white/50 group-hover:border-white transition-colors" />
              <div className="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-white/50 group-hover:border-white transition-colors" />
              <div className="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-white/50 group-hover:border-white transition-colors" />

              <span className="text-sm tracking-[0.3em] font-light group-hover:text-white text-white/70">
                {isLoading
                  ? "INITIALIZING..."
                  : hasPlayed
                    ? "RESUME LINK"
                    : "INITIALIZE LINK"}
              </span>
            </button>
          </>
        ) : (
          <div
            className="w-full flex flex-col gap-12 bg-black/60 border border-white/10"
            style={{ padding: "64px 96px" }}
          >
            <div className="text-2xl tracking-[0.4em] mb-8 text-center border-b border-white/10 pb-8">
              GRAPHICS CONFIG
            </div>

            {/* Resolution */}
            <div className="flex justify-between items-center">
              <div className="text-sm tracking-widest text-white/60">
                RENDER RESOLUTION
              </div>
              <div className="flex gap-2">
                {[1.0, 1.5, 2.0].map((val) => (
                  <button
                    key={val}
                    onClick={() => updateSettings({ renderScale: val })}
                    className={`px-4 py-2 text-xs tracking-widest border ${settings.renderScale === val ? "bg-white text-black border-white" : "bg-transparent text-white/50 border-white/20 hover:border-white/50"}`}
                  >
                    {val === 1.0 ? "ULTRA" : val === 1.5 ? "HIGH" : "PERF"}
                  </button>
                ))}
              </div>
            </div>

            {/* Movement Samples */}
            <div className="flex justify-between items-center">
              <div className="text-sm tracking-widest text-white/60">
                MOVEMENT SAMPLES
              </div>
              <div className="flex gap-2">
                {[1, 2, 4].map((val) => (
                  <button
                    key={val}
                    onClick={() => updateSettings({ samplesWhileMoving: val })}
                    className={`px-4 py-2 text-xs tracking-widest border ${settings.samplesWhileMoving === val ? "bg-white text-black border-white" : "bg-transparent text-white/50 border-white/20 hover:border-white/50"}`}
                  >
                    {val}
                  </button>
                ))}
              </div>
            </div>

            {/* Static Samples */}
            <div className="flex justify-between items-center">
              <div className="text-sm tracking-widest text-white/60">
                STATIC SAMPLES
              </div>
              <div className="flex gap-2">
                {[16, 24, 32, 64].map((val) => (
                  <button
                    key={val}
                    onClick={() => updateSettings({ samplesWhileStill: val })}
                    className={`px-4 py-2 text-xs tracking-widest border ${settings.samplesWhileStill === val ? "bg-white text-black border-white" : "bg-transparent text-white/50 border-white/20 hover:border-white/50"}`}
                  >
                    {val}
                  </button>
                ))}
              </div>
            </div>

            {/* Bounces */}
            <div className="flex justify-between items-center">
              <div className="text-sm tracking-widest text-white/60">
                LIGHT BOUNCES
              </div>
              <div className="flex gap-2">
                {[2, 3, 4].map((val) => (
                  <button
                    key={val}
                    onClick={() => updateSettings({ bounces: val })}
                    className={`px-4 py-2 text-xs tracking-widest border ${settings.bounces === val ? "bg-white text-black border-white" : "bg-transparent text-white/50 border-white/20 hover:border-white/50"}`}
                  >
                    {val}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Aesthetic corner UI */}
      <div className="absolute bottom-8 left-8 text-[10px] text-white/30 tracking-widest">
        SECURE CONNECTION ESTABLISHED
        <br />
        AWAITING USER INPUT...
      </div>
    </div>
  );
}
