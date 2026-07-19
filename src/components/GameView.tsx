import React, { useEffect, useRef, useCallback, useState } from 'react'
import * as THREE from 'three'
import { PointerLockControls } from 'three/examples/jsm/controls/PointerLockControls.js'
import { PathTracer } from '../game/PathTracer'
import { useGameStore } from '../store/gameStore'
import type { ArtifactState } from '../store/gameStore'
import { InteractionManager } from '../game/InteractionManager'
import { AudioManager } from '../game/AudioManager'

export function GameView() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const pathTracerRef = useRef<PathTracer | null>(null)
  const controlsRef = useRef<PointerLockControls | null>(null)
  const interactionManagerRef = useRef<InteractionManager | null>(null)
  const audioRef = useRef<AudioManager | null>(null)

  const isSolved = useGameStore((s) => s.isSolved)
  const setScreen = useGameStore((s) => s.setScreen)
  const setRingAngle = useGameStore((state) => state.setRingAngle)

  // Dragging state
  const draggingRing = useRef<number | null>(null)
  const previousMouseX = useRef(0)
  
  const [photoProgress, setPhotoProgress] = useState(0)

  // Initialize path tracer & controls
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const container = canvas.parentElement!
    canvas.width = container.clientWidth
    canvas.height = container.clientHeight

    const pt = new PathTracer(canvas)
    pathTracerRef.current = pt
    pt.start()
    
    // Load initial scene
    const initialState = useGameStore.getState()
    pt.loadScene(initialState.currentScene)
    
    // Attempt to load HDRI
    pt.loadHDRI('/textures/skybox.hdr')

    // Subscribe to scene changes to hot-swap shaders
    const unsub = useGameStore.subscribe((state, prevState) => {
      if (state.currentScene !== prevState.currentScene) {
        pt.loadScene(state.currentScene)
        setSpawnForScene(state.currentScene)
      }
    })

    pt.updateGeometry(0)

    // Setup PointerLockControls
    const camera = pt.getCamera()
    const controls = new PointerLockControls(camera, document.body)
    controlsRef.current = controls

    // Spawn logic
    const setSpawnForScene = (sceneId: number) => {
      if (sceneId === 1) {
        camera.position.set(45, 15, 45) // Interrogation Room
        camera.lookAt(0, 15, 0)
      } else {
        camera.position.set(0, 15, 25) // Living Room
        camera.lookAt(0, 15, -10)
      }
    }
    setSpawnForScene(initialState.currentScene)

    // Click canvas to lock pointer
    const handleCanvasClick = () => {
      if (!isSolved) controls.lock()
    }
    canvas.addEventListener('click', handleCanvasClick)

    // Unlock pointer acts as a pause menu
    const handleUnlock = () => {
      setScreen('menu')
    }
    controls.addEventListener('unlock', handleUnlock)

    interactionManagerRef.current = new InteractionManager(pt.getCamera(), canvas)

    // Audio
    const audio = new AudioManager()
    audioRef.current = audio

    const handleResize = () => {
      canvas.width = container.clientWidth
      canvas.height = container.clientHeight
      pt.resize()
    }
    window.addEventListener('resize', handleResize)

    // WASD Keys
    let isRenderingPhoto = false
    const keys = new Set<string>()
    const handleKeyDown = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase()
      keys.add(key)
      if (key === 'r' && !isRenderingPhoto) {
        isRenderingPhoto = true
        pt.onPhotoProgress = (samples) => setPhotoProgress(samples)
        pt.onPhotoReady = (dataUrl) => {
          isRenderingPhoto = false
          setPhotoProgress(0)
          const a = document.createElement('a')
          a.href = dataUrl
          a.download = 'pathtraced_screenshot.png'
          a.click()
        }
        pt.startPhotoRender()
      }
    }
    const handleKeyUp = (e: KeyboardEvent) => keys.delete(e.key.toLowerCase())
    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('keyup', handleKeyUp)

    // Animation loop to update controls damping and unlock progress
    let animId = 0
    let currentProgress = 0
    let targetProgress = 0
    let lastTime = performance.now()
    let ambientStarted = false
    let walkPhase = 0
    let baseCameraY = pt.getCamera().position.y

    const animate = () => {
      animId = requestAnimationFrame(animate)
      
      const solved = useGameStore.getState().isSolved
      targetProgress = solved ? 1 : 0
      
      if (Math.abs(currentProgress - targetProgress) > 0.001) {
        currentProgress += (targetProgress - currentProgress) * 0.015 // Slower, dramatic reveal
        pt.updateGeometry(currentProgress)
      } else if (targetProgress === 1 && currentProgress !== 1) {
        currentProgress = 1
        pt.updateGeometry(currentProgress)
      }
      
      // WASD movement
      let isActuallyMoving = false
      const speed = 0.6
      const camera = pt.getCamera()
      const forward = new THREE.Vector3()
      const right = new THREE.Vector3()
      
      camera.getWorldDirection(forward)
      forward.y = 0
      if (forward.lengthSq() > 0) forward.normalize()
      right.crossVectors(camera.up, forward).normalize()
      
      const move = new THREE.Vector3()
      if (keys.has('w') || keys.has('arrowup')) move.add(forward)
      if (keys.has('s') || keys.has('arrowdown')) move.sub(forward)
      if (keys.has('a') || keys.has('arrowleft')) move.add(right)
      if (keys.has('d') || keys.has('arrowright')) move.sub(right)
      
      if (move.lengthSq() > 0 && controls.isLocked && !isRenderingPhoto) {
        move.normalize().multiplyScalar(speed)
        
        // Player Collision Radius
        const r = 2.5
        
        const currentScene = useGameStore.getState().currentScene
        
        const checkCollision = (nx: number, nz: number) => {
          if (currentScene === 1) {
            // 1. Table: X [-25, 25], Z [-15, 15]
            if (nx > -25 - r && nx < 25 + r && nz > -15 - r && nz < 15 + r) return true
            // 2. Player Chair: X [-6, 6], Z [18, 26]
            if (nx > -6 - r && nx < 6 + r && nz > 18 - r && nz < 26 + r) return true
            // 3. Suspect Chair: X [-5, 5], Z [-35, -25]
            if (nx > -5 - r && nx < 5 + r && nz > -35 - r && nz < -25 + r) return true
            // 4. Server Rack: X [-60, -45], Z [-20, 20]
            if (nx > -60 - r && nx < -45 + r && nz > -20 - r && nz < 20 + r) return true
          } else if (currentScene === 2) {
            // 1. Couch: X [-15, 15], Z [-20, 0]
            if (nx > -15 - r && nx < 15 + r && nz > -20 - r && nz < 0 + r) return true
            // 2. Coffee Table: X [-5, 5], Z [-18, -10]
            if (nx > -5 - r && nx < 5 + r && nz > -18 - r && nz < -10 + r) return true
            // 3. TV Stand: X [-5, 25], Z [-38, -34]
            if (nx > -5 - r && nx < 25 + r && nz > -38 - r && nz < -34 + r) return true
          }
          return false
        }

        const bounds = currentScene === 1 ? 58 : 38
        
        let newX = Math.max(-bounds, Math.min(bounds, camera.position.x + move.x))
        if (checkCollision(newX, camera.position.z)) newX = camera.position.x
        
        let newZ = Math.max(-bounds, Math.min(bounds, camera.position.z + move.z))
        if (checkCollision(newX, newZ)) newZ = camera.position.z
        
        camera.position.x = newX
        camera.position.z = newZ
        
        isActuallyMoving = true
      }

      // Audio: footsteps + ambient
      const now = performance.now()
      const dt = now - lastTime
      lastTime = now
      audio.updateVolume()
      audio.updateWalking(isActuallyMoving && controls.isLocked, dt)
      if (!ambientStarted && controls.isLocked) {
        audio.startAmbient()
        ambientStarted = true
      }
      
      // Camera sway and walk animations
      if (isActuallyMoving && controls.isLocked) {
        walkPhase += dt * 0.01 // Adjust speed of walking cycle
      } else {
        // Smoothly return to standing pose (sin(x)=0 when x is multiple of PI)
        const nearestPi = Math.round(walkPhase / Math.PI) * Math.PI
        walkPhase += (nearestPi - walkPhase) * 0.1
      }
      
      // Head bobbing (rolling breaks PointerLockControls)
      camera.position.y = baseCameraY + Math.sin(walkPhase * 2) * 0.5
      
      // Pass phase to PathTracer for mannequin animation
      pt.setWalkPhase(walkPhase)
    }
    animate()

    const handleWheel = (e: WheelEvent) => {
      if (!controls.isLocked || isSolved || isRenderingPhoto) return
      const ringId = interactionManagerRef.current?.getIntersectedRing()
      if (ringId !== undefined && ringId !== null) {
        const state = useGameStore.getState()
        const angle = state.artifact[`ring${ringId}Angle` as keyof ArtifactState] as number
        // Scroll down increases angle, scroll up decreases
        // Snap to exactly 45 degrees for that chunky mechanical feel
        let currentAngle = angle
        const step = 45
        currentAngle = Math.round(currentAngle / step) * step
        setRingAngle(ringId, currentAngle + Math.sign(e.deltaY) * step)
        pt.updateGeometry(0)
        audio.playClick()
      }
    }
    window.addEventListener('wheel', handleWheel)

    return () => {
      unsub()
      cancelAnimationFrame(animId)
      canvas.removeEventListener('click', handleCanvasClick)
      window.removeEventListener('resize', handleResize)
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('keyup', handleKeyUp)
      window.removeEventListener('wheel', handleWheel)
      controls.dispose()
      audio.dispose()
      pt.dispose()
    }
  }, [isSolved])

  return (
    <div className="relative w-full h-screen bg-black overflow-hidden">
      <canvas ref={canvasRef} className="absolute inset-0 w-full h-full block" />
      
      {/* Central Crosshair */}
      <div className="absolute top-1/2 left-1/2 w-1.5 h-1.5 bg-white rounded-full mix-blend-difference -translate-x-1/2 -translate-y-1/2 pointer-events-none z-10 opacity-70" />

      {/* Photo Render Overlay */}
      {photoProgress > 0 && (
        <div className="absolute top-10 left-1/2 -translate-x-1/2 px-6 py-3 bg-black/80 backdrop-blur-md rounded-lg text-white font-mono text-xl z-20 shadow-[0_0_15px_rgba(0,255,150,0.3)] border border-[rgba(0,255,150,0.2)]">
          <div className="text-sm text-gray-400 mb-1 tracking-widest uppercase">Rendering Photo</div>
          <div className="flex items-center gap-4">
            <div className="w-48 h-2 bg-gray-800 rounded-full overflow-hidden">
              <div 
                className="h-full bg-[rgba(0,255,150,0.8)] shadow-[0_0_10px_rgba(0,255,150,0.8)] transition-all duration-75"
                style={{ width: `${(photoProgress / 200) * 100}%` }}
              />
            </div>
            <span>{Math.min(200, Math.floor(photoProgress))} / 200</span>
          </div>
        </div>
      )}
    </div>
  )
}
