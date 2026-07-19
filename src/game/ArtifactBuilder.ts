import * as THREE from 'three'

const MAT_WOOD = 1
const MAT_METAL = 2
const MAT_CONCRETE = 3
const MAT_GOLD = 4
const MAT_GEM = 5

export interface ArtifactState {
  ring1Angle: number
  ring2Angle: number
  ring3Angle: number
}

export class ArtifactBuilder {
  static build(state: ArtifactState, unlockProgress: number = 0) {
    const boxes: { min: THREE.Vector3; max: THREE.Vector3; mat: number }[] = []
    const cylinders: { pos: THREE.Vector3; axis: THREE.Vector3; r: number; h: number; mat: number }[] = []

    // --- ROOM FURNITURE ---
    const tableY = 10
    // Table Top
    boxes.push({ min: new THREE.Vector3(-25, tableY, -15), max: new THREE.Vector3(25, tableY + 1, 15), mat: MAT_WOOD })
    // Table Legs (Concrete or Metal)
    boxes.push({ min: new THREE.Vector3(-24, 0, -14), max: new THREE.Vector3(-22, tableY, -12), mat: MAT_METAL })
    boxes.push({ min: new THREE.Vector3(22, 0, -14), max: new THREE.Vector3(24, tableY, -12), mat: MAT_METAL })
    boxes.push({ min: new THREE.Vector3(-24, 0, 12), max: new THREE.Vector3(-22, tableY, 14), mat: MAT_METAL })
    boxes.push({ min: new THREE.Vector3(22, 0, 12), max: new THREE.Vector3(24, tableY, 14), mat: MAT_METAL })

    // A simple chair (Wood & Metal)
    boxes.push({ min: new THREE.Vector3(-6, 6, 18), max: new THREE.Vector3(6, 7, 26), mat: MAT_WOOD })
    boxes.push({ min: new THREE.Vector3(-6, 7, 25), max: new THREE.Vector3(6, 16, 26), mat: MAT_WOOD })
    cylinders.push({ pos: new THREE.Vector3(-5, 3, 19), axis: new THREE.Vector3(0, 1, 0), r: 0.5, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(5, 3, 19), axis: new THREE.Vector3(0, 1, 0), r: 0.5, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(-5, 3, 25), axis: new THREE.Vector3(0, 1, 0), r: 0.5, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(5, 3, 25), axis: new THREE.Vector3(0, 1, 0), r: 0.5, h: 6, mat: MAT_METAL })

    // --- THE ARTIFACT ---
    const artY = tableY + 1
    
    // Core structure splits in half and slides horizontally
    const splitX = unlockProgress * 8
    
    // Left Half
    boxes.push({
      min: new THREE.Vector3(-4 - splitX, artY + 2, -4),
      max: new THREE.Vector3(0 - splitX, artY + 18, 4),
      mat: MAT_CONCRETE
    })
    
    // Right Half
    boxes.push({
      min: new THREE.Vector3(0 + splitX, artY + 2, -4),
      max: new THREE.Vector3(4 + splitX, artY + 18, 4),
      mat: MAT_CONCRETE
    })

    // If unlocked, show the GLOWING Ethereal Gem in the center
    if (unlockProgress > 0) {
      boxes.push({
        min: new THREE.Vector3(-2, artY + 2, -2),
        max: new THREE.Vector3(2, artY + 8, 2),
        mat: MAT_GEM
      })
    }

    // Rings move outward based on unlock progress
    const ringExpand = unlockProgress * 4

    // Bottom Ring
    cylinders.push({ pos: new THREE.Vector3(0, artY + 5, 0), axis: new THREE.Vector3(0, 1, 0), r: 7.5 + ringExpand, h: 1.5, mat: MAT_METAL })
    const r1Rads = (state.ring1Angle * Math.PI) / 180
    cylinders.push({ pos: new THREE.Vector3(Math.cos(r1Rads) * (7.5 + ringExpand), artY + 5, Math.sin(r1Rads) * (7.5 + ringExpand)), axis: new THREE.Vector3(Math.cos(r1Rads), 0, Math.sin(r1Rads)), r: 1.2, h: 2, mat: MAT_GOLD })

    // Middle Ring
    cylinders.push({ pos: new THREE.Vector3(0, artY + 10, 0), axis: new THREE.Vector3(0, 1, 0), r: 7.0 + ringExpand, h: 1.5, mat: MAT_METAL })
    const r2Rads = (state.ring2Angle * Math.PI) / 180
    cylinders.push({ pos: new THREE.Vector3(Math.cos(r2Rads) * (7.0 + ringExpand), artY + 10, Math.sin(r2Rads) * (7.0 + ringExpand)), axis: new THREE.Vector3(Math.cos(r2Rads), 0, Math.sin(r2Rads)), r: 1.0, h: 2, mat: MAT_GOLD })

    // Top Ring
    cylinders.push({ pos: new THREE.Vector3(0, artY + 15, 0), axis: new THREE.Vector3(0, 1, 0), r: 6.5 + ringExpand, h: 1.5, mat: MAT_METAL })
    const r3Rads = (state.ring3Angle * Math.PI) / 180
    cylinders.push({ pos: new THREE.Vector3(Math.cos(r3Rads) * (6.5 + ringExpand), artY + 15, Math.sin(r3Rads) * (6.5 + ringExpand)), axis: new THREE.Vector3(Math.cos(r3Rads), 0, Math.sin(r3Rads)), r: 1.0, h: 2, mat: MAT_GOLD })

    // --- ROOM DETAILS ---
    // 1. Window Frame & Sci-Fi Metal Bars (Z = -60 wall)
    boxes.push({ min: new THREE.Vector3(-26, 14, -60), max: new THREE.Vector3(26, 15, -58), mat: MAT_METAL }) // Bottom Sill
    boxes.push({ min: new THREE.Vector3(-26, 45, -60), max: new THREE.Vector3(26, 46, -58), mat: MAT_METAL }) // Top Frame
    boxes.push({ min: new THREE.Vector3(-26, 15, -60), max: new THREE.Vector3(-24, 45, -58), mat: MAT_METAL }) // Left Frame
    boxes.push({ min: new THREE.Vector3(24, 15, -60), max: new THREE.Vector3(26, 45, -58), mat: MAT_METAL }) // Right Frame
    // Central Crossbars
    boxes.push({ min: new THREE.Vector3(-1.5, 15, -60), max: new THREE.Vector3(1.5, 45, -59), mat: MAT_METAL }) // Vertical Bar
    boxes.push({ min: new THREE.Vector3(-24, 29, -60), max: new THREE.Vector3(24, 31, -59), mat: MAT_METAL }) // Horizontal Bar

    // 2. Server Rack / Industrial Shelves on Left Wall (X = -58)
    boxes.push({ min: new THREE.Vector3(-60, 0, -20), max: new THREE.Vector3(-45, 50, 20), mat: MAT_METAL }) // Main Frame
    boxes.push({ min: new THREE.Vector3(-45, 10, -18), max: new THREE.Vector3(-43, 12, 18), mat: MAT_CONCRETE }) // Shelf 1
    boxes.push({ min: new THREE.Vector3(-45, 25, -18), max: new THREE.Vector3(-43, 27, 18), mat: MAT_CONCRETE }) // Shelf 2
    boxes.push({ min: new THREE.Vector3(-45, 40, -18), max: new THREE.Vector3(-43, 42, 18), mat: MAT_CONCRETE }) // Shelf 3

    // 3. Opposing Interrogation Chair
    const chair2Z = -30
    boxes.push({ min: new THREE.Vector3(-5, 6, chair2Z - 5), max: new THREE.Vector3(5, 7, chair2Z + 5), mat: MAT_WOOD }) // Seat
    boxes.push({ min: new THREE.Vector3(-5, 7, chair2Z - 6), max: new THREE.Vector3(5, 18, chair2Z - 4), mat: MAT_WOOD }) // Back
    cylinders.push({ pos: new THREE.Vector3(-4, 3, chair2Z - 4), axis: new THREE.Vector3(0, 1, 0), r: 0.8, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(4, 3, chair2Z - 4), axis: new THREE.Vector3(0, 1, 0), r: 0.8, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(-4, 3, chair2Z + 4), axis: new THREE.Vector3(0, 1, 0), r: 0.8, h: 6, mat: MAT_METAL })
    cylinders.push({ pos: new THREE.Vector3(4, 3, chair2Z + 4), axis: new THREE.Vector3(0, 1, 0), r: 0.8, h: 6, mat: MAT_METAL })

    return {
      numBoxes: boxes.length,
      boxMins: boxes.map((b) => b.min),
      boxMaxs: boxes.map((b) => b.max),
      boxMats: boxes.map((b) => b.mat),
      numCylinders: cylinders.length,
      cylPos: cylinders.map((c) => c.pos),
      cylAxis: cylinders.map((c) => c.axis),
      cylRadii: cylinders.map((c) => c.r),
      cylHeights: cylinders.map((c) => c.h),
      cylMats: cylinders.map((c) => c.mat),
    }
  }
}
