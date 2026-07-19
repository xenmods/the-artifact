import { useGameStore } from './store/gameStore'
import { MainMenu } from './components/MainMenu'
import { GameView } from './components/GameView'
import { HUD } from './components/HUD'

export default function App() {
  const screen = useGameStore((s) => s.screen)

  return (
    <div className="w-screen h-screen overflow-hidden bg-void relative">
      <GameView />
      {screen === 'game' && <HUD />}
      {screen === 'menu' && <MainMenu />}
      
      <div className="absolute inset-0 pointer-events-none noise-overlay mix-blend-overlay opacity-30 z-50"></div>
    </div>
  )
}
