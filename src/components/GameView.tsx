import React, { useEffect, useRef, useCallback } from 'react'
import * as THREE from 'three'
import { PointerLockControls } from 'three/examples/jsm/controls/PointerLockControls'
import { PathTracer } from '../game/PathTracer'
import { useGameStore } from '../store/gameStore'
import type { ArtifactState } from '../store/gameStore'
import { InteractionManager } from '../game/InteractionManager'

export function GameView() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const pathTracerRef = useRef<PathTracer | null>(null)
  const controlsRef = useRef<PointerLockControls | null>(null)
  const interactionManagerRef = useRef<InteractionManager | null>(null)

  const isSolved = useGameStore((s) => s.isSolved)
  const setScreen = useGameStore((s) => s.setScreen)
  const setRingAngle = useGameStore((state) => state.setRingAngle)

  // Dragging state
  const draggingRing = useRef<number | null>(null)
  const previousMouseX = useRef(0)

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
    pt.updateGeometry(0)

    // Setup PointerLockControls
    const camera = pt.getCamera()
    camera.position.set(45, 15, 45) // Spawn in back right corner
    camera.lookAt(0, 15, 0) // Look at artifact table
    const controls = new PointerLockControls(camera, document.body)
    controlsRef.current = controls

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

    const handleResize = () => {
      canvas.width = container.clientWidth
      canvas.height = container.clientHeight
      pt.resize()
    }
    window.addEventListener('resize', handleResize)

    // WASD Keys
    const keys = new Set<string>()
    const handleKeyDown = (e: KeyboardEvent) => keys.add(e.key.toLowerCase())
    const handleKeyUp = (e: KeyboardEvent) => keys.delete(e.key.toLowerCase())
    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('keyup', handleKeyUp)

    // Animation loop to update controls damping and unlock progress
    let animId = 0
    let currentProgress = 0
    let targetProgress = 0

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
      
      if (move.lengthSq() > 0 && controls.isLocked) {
        move.normalize().multiplyScalar(speed)
        
        // Player Collision Radius
        const r = 2.5
        
        const checkCollision = (nx: number, nz: number) => {
          // 1. Table: X [-25, 25], Z [-15, 15]
          if (nx > -25 - r && nx < 25 + r && nz > -15 - r && nz < 15 + r) return true
          // 2. Player Chair: X [-6, 6], Z [18, 26]
          if (nx > -6 - r && nx < 6 + r && nz > 18 - r && nz < 26 + r) return true
          // 3. Suspect Chair: X [-5, 5], Z [-35, -25]
          if (nx > -5 - r && nx < 5 + r && nz > -35 - r && nz < -25 + r) return true
          // 4. Server Rack: X [-60, -45], Z [-20, 20]
          if (nx > -60 - r && nx < -45 + r && nz > -20 - r && nz < 20 + r) return true
          
          return false
        }

        const bound = 55
        let newX = Math.max(-bound, Math.min(bound, camera.position.x + move.x))
        if (checkCollision(newX, camera.position.z)) newX = camera.position.x // Slide along Z if X is blocked
        
        let newZ = Math.max(-bound, Math.min(bound, camera.position.z + move.z))
        if (checkCollision(newX, newZ)) newZ = camera.position.z // Use newX here to check corner collision
        
        // Update via controls since it manages position differently
        camera.position.x = newX
        camera.position.z = newZ
      }
    }
    animate()

    const handleWheel = (e: WheelEvent) => {
      if (!controls.isLocked || isSolved) return
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
      }
    }
    window.addEventListener('wheel', handleWheel)

    return () => {
      canvas.removeEventListener('click', handleCanvasClick)
      window.removeEventListener('resize', handleResize)
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('keyup', handleKeyUp)
      window.removeEventListener('wheel', handleWheel)
      cancelAnimationFrame(animId)
      controls.dispose()
      pt.dispose()
    }
  }, [isSolved])

  return (
    <div className="relative w-full h-screen bg-black overflow-hidden">
      <canvas ref={canvasRef} className="absolute inset-0 w-full h-full block" />
      
      {/* Central Crosshair */}
      <div className="absolute top-1/2 left-1/2 w-1.5 h-1.5 bg-white rounded-full mix-blend-difference -translate-x-1/2 -translate-y-1/2 pointer-events-none z-10 opacity-70" />
    </div>
  )
}
