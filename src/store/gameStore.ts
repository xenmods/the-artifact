import { create } from 'zustand'

export type Screen = 'menu' | 'game'

export interface ArtifactState {
  ring1Angle: number
  ring2Angle: number
  ring3Angle: number
}

export interface GraphicsSettings {
  renderScale: number
  samplesWhileMoving: number
  samplesWhileStill: number
  bounces: number
}

interface GameState {
  screen: Screen
  setScreen: (screen: Screen) => void

  isLoading: boolean
  setIsLoading: (loading: boolean) => void
  loadingProgress: number
  setLoadingProgress: (progress: number) => void

  hasPlayed: boolean
  setHasPlayed: (played: boolean) => void

  settings: GraphicsSettings
  updateSettings: (newSettings: Partial<GraphicsSettings>) => void

  // Artifact Rotation State
  artifact: ArtifactState
  setRingAngle: (ring: number, angle: number) => void
  
  isSolved: boolean
  checkSolved: () => void
}

export const useGameStore = create<GameState>((set, get) => ({
  screen: 'menu',
  setScreen: (screen) => set({ screen }),

  isLoading: true,
  setIsLoading: (loading) => set({ isLoading: loading }),
  loadingProgress: 0,
  setLoadingProgress: (progress) => set({ loadingProgress: progress }),

  hasPlayed: false,
  setHasPlayed: (played) => set({ hasPlayed: played }),

  settings: {
    renderScale: 1.5,
    samplesWhileMoving: 4,
    samplesWhileStill: 24,
    bounces: 3,
  },
  updateSettings: (newSettings) => 
    set((state) => ({ settings: { ...state.settings, ...newSettings } })),

  artifact: {
    ring1Angle: 120, // Scrambled initial state
    ring2Angle: 45,
    ring3Angle: -90,
  },

  setRingAngle: (ring, angle) => {
    set((state) => ({
      artifact: {
        ...state.artifact,
        [`ring${ring}Angle`]: angle,
      },
    }))
    get().checkSolved()
  },

  isSolved: false,
  checkSolved: () => {
    const { artifact } = get()
    // Win condition: All rings aligned at 90 degrees (facing camera)
    const tol = 10
    const normalize = (a: number) => ((a % 360) + 360) % 360
    const r1 = normalize(artifact.ring1Angle)
    const r2 = normalize(artifact.ring2Angle)
    const r3 = normalize(artifact.ring3Angle)

    const isClose = (val: number, target: number) => {
      const diff = Math.abs(val - target)
      return diff < tol || Math.abs(diff - 360) < tol
    }

    if (isClose(r1, 90) && isClose(r2, 90) && isClose(r3, 90)) {
      if (!get().isSolved) set({ isSolved: true })
    } else {
      if (get().isSolved) set({ isSolved: false })
    }
  },
}))
