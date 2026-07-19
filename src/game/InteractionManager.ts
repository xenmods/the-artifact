import * as THREE from 'three'

export class InteractionManager {
  private raycaster = new THREE.Raycaster()
  private mouse = new THREE.Vector2()
  private canvas: HTMLCanvasElement
  private camera: THREE.PerspectiveCamera

  constructor(camera: THREE.PerspectiveCamera, canvas: HTMLCanvasElement) {
    this.camera = camera
    this.canvas = canvas
  }
  
  // Define the rings for raycasting (artY is 11)
  private rings = [
    { id: 1, pos: new THREE.Vector3(0, 16, 0), r: 6, h: 3 },
    { id: 2, pos: new THREE.Vector3(0, 21, 0), r: 5.5, h: 3 },
    { id: 3, pos: new THREE.Vector3(0, 26, 0), r: 5, h: 3 }
  ]

  public getIntersectedRing(): number | null {
    // With PointerLockControls, we always raycast from the exact center of the screen
    this.mouse.set(0, 0)

    this.raycaster.setFromCamera(this.mouse, this.camera)
    const ro = this.raycaster.ray.origin
    const rd = this.raycaster.ray.direction

    let closest = Infinity
    let hitId: number | null = null

    // Ray vs Cylinder intersection (axis-aligned to Y)
    for (const ring of this.rings) {
      const t = this.intersectCylinderY(ring.pos, ring.r, ring.h, ro, rd)
      if (t > 0 && t < closest) {
        closest = t
        hitId = ring.id
      }
    }

    return hitId
  }

  private intersectCylinderY(pos: THREE.Vector3, r: number, h: number, ro: THREE.Vector3, rd: THREE.Vector3): number {
    const dx = rd.x
    const dz = rd.z
    const a = dx * dx + dz * dz
    const bx = ro.x - pos.x
    const bz = ro.z - pos.z
    const b = 2.0 * (bx * dx + bz * dz)
    const c = bx * bx + bz * bz - r * r

    let disc = b * b - 4.0 * a * c
    if (disc < 0) return -1

    disc = Math.sqrt(disc)
    let t1 = (-b - disc) / (2.0 * a)
    let t2 = (-b + disc) / (2.0 * a)
    
    let t = t1
    if (t < 0) t = t2
    if (t < 0) return -1

    const hitY = ro.y + rd.y * t
    if (hitY >= pos.y - h / 2 && hitY <= pos.y + h / 2) {
      return t
    }

    return -1
  }
}
