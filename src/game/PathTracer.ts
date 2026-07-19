import * as THREE from 'three'
import pathtracingVertSrc from '../shaders/pathtracing.vert.glsl'
import pathtracingFragSrc from '../shaders/pathtracing.frag.glsl'
import { useGameStore } from '../store/gameStore'
import type { TimeOfDay } from '../store/gameStore'
import { ArtifactBuilder } from './ArtifactBuilder'
import screencopyFragSrc from '../shaders/screencopy.frag.glsl'
import screenoutputFragSrc from '../shaders/screenoutput.frag.glsl'
import denoiseFragSrc from '../shaders/denoise.frag.glsl'

export interface ArtifactUniforms {
  numBoxes: number
  boxMins: THREE.Vector3[]
  boxMaxs: THREE.Vector3[]
  boxMats: number[]

  numCylinders: number
  cylPos: THREE.Vector3[]
  cylAxis: THREE.Vector3[]
  cylRadii: number[]
  cylHeights: number[]
  cylMats: number[]
}

export class PathTracer {
  private renderer: THREE.WebGLRenderer
  private scene: THREE.Scene
  private orthoCamera: THREE.OrthographicCamera
  private canvas: HTMLCanvasElement
  private fullscreenQuad!: THREE.Mesh
  private pathTracingMaterial!: THREE.ShaderMaterial
  private screenCopyMaterial!: THREE.ShaderMaterial
  private screenOutputMaterial!: THREE.ShaderMaterial

  private renderTargetA!: THREE.WebGLRenderTarget
  private renderTargetB!: THREE.WebGLRenderTarget

  private screenCopyScene!: THREE.Scene
  private screenOutputScene!: THREE.Scene
  private screenCopyQuad!: THREE.Mesh
  private screenOutputQuad!: THREE.Mesh

  private denoiseRenderTarget!: THREE.WebGLRenderTarget
  private denoiseMaterial!: THREE.ShaderMaterial
  private denoiseScene!: THREE.Scene
  private denoiseQuad!: THREE.Mesh

  private sampleCounter = 1.0
  private frameCounter = 0.0
  private sceneIsDynamic = false
  private animationId = 0
  private width = 0
  private height = 0
  private prevTimeOfDay = 'noon'

  private prevCameraMatrix = new THREE.Matrix4()
  private viewCamera: THREE.PerspectiveCamera
  
  private texturesLoaded = false

  // Downsample to increase performance drastically
  private renderScale = 1.5

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      context: canvas.getContext('webgl2', {
        alpha: false,
        antialias: false,
        powerPreference: 'high-performance',
      }) as WebGL2RenderingContext,
    })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.0))
    this.renderer.autoClear = false

    this.scene = new THREE.Scene()
    this.orthoCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1)

    // Interrogation desk camera setup
    this.viewCamera = new THREE.PerspectiveCamera(40, 1, 0.1, 1000)
    this.viewCamera.position.set(0, 25, 30)
    this.viewCamera.lookAt(0, 18, 0)


    this.initRenderTargets()
    this.initMaterials()
    this.initQuads()
    this.loadTextures()
  }

  private initRenderTargets() {
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    this.width = w
    this.height = h

    const rtW = Math.floor(w / this.renderScale)
    const rtH = Math.floor(h / this.renderScale)

    const opts: THREE.RenderTargetOptions = {
      minFilter: THREE.NearestFilter,
      magFilter: THREE.NearestFilter,
      type: THREE.FloatType,
      format: THREE.RGBAFormat,
    }

    this.renderTargetA = new THREE.WebGLRenderTarget(rtW, rtH, opts)
    this.renderTargetB = new THREE.WebGLRenderTarget(rtW, rtH, opts)
    this.denoiseRenderTarget = new THREE.WebGLRenderTarget(rtW, rtH, opts)
  }

  private padVec3(arr: THREE.Vector3[], size: number): THREE.Vector3[] {
    const res = [...arr]
    while (res.length < size) res.push(new THREE.Vector3())
    return res
  }
  private padFloat(arr: number[], size: number): number[] {
    const res = [...arr]
    while (res.length < size) res.push(0)
    return res
  }
  private padInt(arr: number[], size: number): number[] {
    const res = [...arr]
    while (res.length < size) res.push(0)
    return res
  }

  private initMaterials() {
    const fov = this.viewCamera.fov
    const uVLen = Math.tan((fov * 0.5) * (Math.PI / 180.0))
    const uULen = uVLen * (this.width / Math.max(this.height, 1))

    this.pathTracingMaterial = new THREE.ShaderMaterial({
      vertexShader: pathtracingVertSrc,
      fragmentShader: pathtracingFragSrc,
      uniforms: {
        tPreviousTexture: { value: this.renderTargetA.texture },
        uCameraMatrix: { value: new THREE.Matrix4() },
        uResolution: { value: new THREE.Vector2(this.width, this.height) },
        uRandomVec2: { value: new THREE.Vector2() },
        uEPS_intersect: { value: 0.01 },
        uTime: { value: 0 },
        uSampleCounter: { value: 1.0 },
        uFrameCounter: { value: 0.0 },
        uULen: { value: uULen },
        uVLen: { value: uVLen },
        uCameraIsMoving: { value: false },
        uSamplesPerFrame: { value: 2 },
        uWalkPhase: { value: 0.0 },

        // Textures placeholder
        tWoodColor: { value: null }, tWoodNormal: { value: null }, tWoodRoughness: { value: null },
        tMetalColor: { value: null }, tMetalNormal: { value: null }, tMetalRoughness: { value: null },
        tConcreteColor: { value: null }, tConcreteNormal: { value: null }, tConcreteRoughness: { value: null },
        tMarbleColor: { value: null }, tMarbleNormal: { value: null }, tMarbleRoughness: { value: null },

        // Artifact arrays
        uNumBoxes: { value: 0 },
        uBoxMins: { value: this.padVec3([], 32) },
        uBoxMaxs: { value: this.padVec3([], 32) },
        uBoxMats: { value: this.padInt([], 32) },

        uNumCylinders: { value: 0 },
        uCylPos: { value: this.padVec3([], 32) },
        uCylAxis: { value: this.padVec3([], 32) },
        uCylRadii: { value: this.padFloat([], 32) },
        uCylHeights: { value: this.padFloat([], 32) },
        uCylMats: { value: this.padInt([], 32) },

        // Room/Light
        uRoomMin: { value: new THREE.Vector3(-60, -1, -60) },
        uRoomMax: { value: new THREE.Vector3(60, 60, 60) },
        uLightPos: { value: new THREE.Vector3(20, 50, -100) },
        uLightColor: { value: new THREE.Vector3(1.0, 0.85, 0.6) }, // Warm sunlight
        uLightRadius: { value: 12 },
        uMaxBounces: { value: 3 },
      },
      depthTest: false,
      depthWrite: false,
      glslVersion: THREE.GLSL3,
    })

    this.screenCopyMaterial = new THREE.ShaderMaterial({
      vertexShader: pathtracingVertSrc,
      fragmentShader: screencopyFragSrc,
      uniforms: { tTexture: { value: this.renderTargetB.texture } },
      depthTest: false, depthWrite: false, glslVersion: THREE.GLSL3,
    })

    this.screenOutputMaterial = new THREE.ShaderMaterial({
      vertexShader: pathtracingVertSrc,
      fragmentShader: screenoutputFragSrc,
      uniforms: {
        tTexture: { value: this.renderTargetB.texture },
        uToneMappingExposure: { value: 2.5 }, // Increased for brighter room
        uPixelEdgeSharpness: { value: 0.5 },
        uResolution: { value: new THREE.Vector2(this.width, this.height) },
      },
      depthTest: false, depthWrite: false, glslVersion: THREE.GLSL3,
    })

    this.denoiseMaterial = new THREE.ShaderMaterial({
      vertexShader: pathtracingVertSrc,
      fragmentShader: denoiseFragSrc,
      uniforms: {
        tInput: { value: this.renderTargetB.texture },
        uResolution: { value: new THREE.Vector2(this.width, this.height) },
      },
      depthTest: false, depthWrite: false, glslVersion: THREE.GLSL3,
    })
  }
  
  private loadTextures() {
    const manager = new THREE.LoadingManager()
    
    manager.onProgress = (url, itemsLoaded, itemsTotal) => {
      const progress = Math.round((itemsLoaded / itemsTotal) * 100)
      useGameStore.getState().setLoadingProgress(progress)
    }

    manager.onLoad = () => {
      this.texturesLoaded = true
      useGameStore.getState().setIsLoading(false)
      this.resetAccumulation()
    }

    const loader = new THREE.TextureLoader(manager)
    const loadTex = (url: string) => {
        const tex = loader.load(url)
        tex.wrapS = THREE.RepeatWrapping
        tex.wrapT = THREE.RepeatWrapping
        return tex
    }

    // Wood
    this.pathTracingMaterial.uniforms.tWoodColor.value = loadTex('/textures/wood/Wood095_1K-JPG_Color.jpg')
    this.pathTracingMaterial.uniforms.tWoodNormal.value = loadTex('/textures/wood/Wood095_1K-JPG_NormalGL.jpg')
    this.pathTracingMaterial.uniforms.tWoodRoughness.value = loadTex('/textures/wood/Wood095_1K-JPG_Roughness.jpg')

    // Metal
    this.pathTracingMaterial.uniforms.tMetalColor.value = loadTex('/textures/metal/Metal063_1K-JPG_Color.jpg')
    this.pathTracingMaterial.uniforms.tMetalNormal.value = loadTex('/textures/metal/Metal063_1K-JPG_NormalGL.jpg')
    this.pathTracingMaterial.uniforms.tMetalRoughness.value = loadTex('/textures/metal/Metal063_1K-JPG_Roughness.jpg')

    // Concrete (Now using Wood051 for walls/core)
    this.pathTracingMaterial.uniforms.tConcreteColor.value = loadTex('/textures/wood051/Wood051_1K-JPG_Color.jpg')
    this.pathTracingMaterial.uniforms.tConcreteNormal.value = loadTex('/textures/wood051/Wood051_1K-JPG_NormalGL.jpg')
    this.pathTracingMaterial.uniforms.tConcreteRoughness.value = loadTex('/textures/wood051/Wood051_1K-JPG_Roughness.jpg')

    // Marble015 for the floor
    this.pathTracingMaterial.uniforms.tMarbleColor.value = loadTex('/textures/marble015/Marble015_1K-JPG_Color.jpg')
    this.pathTracingMaterial.uniforms.tMarbleNormal.value = loadTex('/textures/marble015/Marble015_1K-JPG_NormalGL.jpg')
    this.pathTracingMaterial.uniforms.tMarbleRoughness.value = loadTex('/textures/marble015/Marble015_1K-JPG_Roughness.jpg')
  }

  public setWalkPhase(phase: number) {
    if (this.pathTracingMaterial) {
      this.pathTracingMaterial.uniforms.uWalkPhase.value = phase
    }
  }

  public updateGeometry(unlockProgress: number = 0) {
    const state = useGameStore.getState().artifact
    const sceneData = ArtifactBuilder.build(state, unlockProgress)

    this.pathTracingMaterial.uniforms.uNumBoxes.value = sceneData.numBoxes
    this.pathTracingMaterial.uniforms.uBoxMins.value = this.padVec3(sceneData.boxMins, 32)
    this.pathTracingMaterial.uniforms.uBoxMaxs.value = this.padVec3(sceneData.boxMaxs, 32)
    this.pathTracingMaterial.uniforms.uBoxMats.value = this.padInt(sceneData.boxMats, 32)

    this.pathTracingMaterial.uniforms.uNumCylinders.value = sceneData.numCylinders
    this.pathTracingMaterial.uniforms.uCylPos.value = this.padVec3(sceneData.cylPos, 32)
    this.pathTracingMaterial.uniforms.uCylAxis.value = this.padVec3(sceneData.cylAxis, 32)
    this.pathTracingMaterial.uniforms.uCylRadii.value = this.padFloat(sceneData.cylRadii, 32)
    this.pathTracingMaterial.uniforms.uCylHeights.value = this.padFloat(sceneData.cylHeights, 32)
    this.pathTracingMaterial.uniforms.uCylMats.value = this.padInt(sceneData.cylMats, 32)
    
    this.resetAccumulation()
  }

  private initQuads() {
    const geo = new THREE.PlaneGeometry(2, 2)
    this.fullscreenQuad = new THREE.Mesh(geo, this.pathTracingMaterial)
    this.scene.add(this.fullscreenQuad)

    this.screenCopyScene = new THREE.Scene()
    this.screenCopyQuad = new THREE.Mesh(geo, this.screenCopyMaterial)
    this.screenCopyScene.add(this.screenCopyQuad)

    this.screenOutputScene = new THREE.Scene()
    this.screenOutputQuad = new THREE.Mesh(geo, this.screenOutputMaterial)
    this.screenOutputScene.add(this.screenOutputQuad)

    this.denoiseScene = new THREE.Scene()
    this.denoiseQuad = new THREE.Mesh(geo, this.denoiseMaterial)
    this.denoiseScene.add(this.denoiseQuad)
  }

  resetAccumulation() {
    this.sampleCounter = 1.0
    this.sceneIsDynamic = true
  }

  resize() {
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    const scale = useGameStore.getState().settings.renderScale

    if (w === this.width && h === this.height && scale === this.renderScale) return

    this.width = w
    this.height = h
    this.renderScale = scale

    this.renderer.setSize(w, h, false) // Ensure it uses CSS size
    this.viewCamera.aspect = w / h
    this.viewCamera.updateProjectionMatrix()

    const rtW = Math.floor(w / this.renderScale)
    const rtH = Math.floor(h / this.renderScale)
    
    this.renderTargetA.setSize(rtW, rtH)
    this.renderTargetB.setSize(rtW, rtH)
    this.denoiseRenderTarget.setSize(rtW, rtH)

    if (this.pathTracingMaterial) {
      this.pathTracingMaterial.uniforms.uResolution.value.set(w, h)
      const fov = this.viewCamera.fov
      const uVLen = Math.tan((fov * 0.5) * (Math.PI / 180.0))
      const uULen = uVLen * (w / Math.max(h, 1))
      this.pathTracingMaterial.uniforms.uULen.value = uULen
      this.pathTracingMaterial.uniforms.uVLen.value = uVLen
    }
    this.screenOutputMaterial.uniforms.uResolution.value.set(w, h)

    this.resetAccumulation()
  }

  private render = () => {
    this.animationId = requestAnimationFrame(this.render)
    if (!this.texturesLoaded) return // Wait for textures
    this.resize()

    this.frameCounter++

    // Check if camera moved with an epsilon to avoid OrbitControls micro-damping constantly resetting noise
    let isMoving = false
    for (let i = 0; i < 16; i++) {
      if (Math.abs(this.viewCamera.matrixWorld.elements[i] - this.prevCameraMatrix.elements[i]) > 0.0001) {
        isMoving = true
        break
      }
    }

    if (isMoving || !this.texturesLoaded) {
      this.resetAccumulation()
      this.prevCameraMatrix.copy(this.viewCamera.matrixWorld)
    }

    // Time reference for shader
    const time = performance.now() * 0.001

    this.pathTracingMaterial.uniforms.uCameraMatrix.value.copy(this.viewCamera.matrixWorld)
    
    const settings = useGameStore.getState().settings

    // Time of day lighting — reset accumulation if it changed
    if (settings.timeOfDay !== this.prevTimeOfDay) {
      this.prevTimeOfDay = settings.timeOfDay
      this.resetAccumulation()
    }
    this.applyTimeOfDay(settings.timeOfDay)

    if (isMoving || this.sceneIsDynamic) {
      this.pathTracingMaterial.uniforms.uCameraIsMoving.value = true
      this.pathTracingMaterial.uniforms.uSamplesPerFrame.value = settings.samplesWhileMoving 
    } else {
      this.pathTracingMaterial.uniforms.uCameraIsMoving.value = false
      this.pathTracingMaterial.uniforms.uSamplesPerFrame.value = settings.samplesWhileStill
    }

    this.pathTracingMaterial.uniforms.uMaxBounces.value = settings.bounces
    
    this.pathTracingMaterial.uniforms.uSampleCounter.value = this.sampleCounter
    this.pathTracingMaterial.uniforms.uFrameCounter.value = this.frameCounter
    this.pathTracingMaterial.uniforms.uTime.value = time
    this.pathTracingMaterial.uniforms.uRandomVec2.value.set(Math.random(), Math.random())

    // Pass 1: Path trace into B
    this.pathTracingMaterial.uniforms.tPreviousTexture.value = this.renderTargetA.texture
    this.renderer.setRenderTarget(this.renderTargetB)
    this.renderer.render(this.scene, this.orthoCamera)

    // Pass 2: Copy B into A for accumulation
    this.screenCopyMaterial.uniforms.tTexture.value = this.renderTargetB.texture
    this.renderer.setRenderTarget(this.renderTargetA)
    this.renderer.render(this.screenCopyScene, this.orthoCamera)

    // Pass 3 (conditional): Denoise B, or pass B directly to screen output
    if (settings.denoiserEnabled) {
      this.denoiseMaterial.uniforms.tInput.value = this.renderTargetB.texture
      this.denoiseMaterial.uniforms.uResolution.value.set(
        Math.floor(this.width / this.renderScale),
        Math.floor(this.height / this.renderScale)
      )
      this.renderer.setRenderTarget(this.denoiseRenderTarget)
      this.renderer.render(this.denoiseScene, this.orthoCamera)

      this.screenOutputMaterial.uniforms.tTexture.value = this.denoiseRenderTarget.texture
    } else {
      this.screenOutputMaterial.uniforms.tTexture.value = this.renderTargetB.texture
    }

    // Final pass: Screen output
    this.renderer.setRenderTarget(null)
    this.renderer.render(this.screenOutputScene, this.orthoCamera)

    this.sampleCounter++
    if (this.sceneIsDynamic && this.sampleCounter > 2) {
      this.sceneIsDynamic = false
    }
  }

  start() { this.render() }
  stop() { cancelAnimationFrame(this.animationId) }
  dispose() {
    this.stop()
    this.renderTargetA.dispose()
    this.renderTargetB.dispose()
    this.denoiseRenderTarget.dispose()
    this.pathTracingMaterial.dispose()
    this.screenCopyMaterial.dispose()
    this.screenOutputMaterial.dispose()
    this.denoiseMaterial.dispose()
    this.renderer.dispose()
  }
  getCamera() { return this.viewCamera }

  private applyTimeOfDay(tod: TimeOfDay) {
    const u = this.pathTracingMaterial.uniforms
    switch (tod) {
      case 'dawn':
        u.uLightPos.value.set(-40, 25, -60)
        u.uLightColor.value.set(1.0, 0.65, 0.45)
        u.uLightRadius.value = 15
        break
      case 'noon':
        u.uLightPos.value.set(20, 50, -100)
        u.uLightColor.value.set(1.0, 0.95, 0.9)
        u.uLightRadius.value = 16
        break
      case 'evening':
        u.uLightPos.value.set(50, 15, -40)
        u.uLightColor.value.set(1.0, 0.45, 0.15)
        u.uLightRadius.value = 18
        break
      case 'night':
        u.uLightPos.value.set(0, 55, 0)
        u.uLightColor.value.set(0.35, 0.45, 0.75)
        u.uLightRadius.value = 8
        break
    }
  }
}
