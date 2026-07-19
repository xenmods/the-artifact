import { useGameStore } from '../store/gameStore'

export class AudioManager {
  private ctx: AudioContext | null = null
  private masterGain: GainNode | null = null
  private ambientSource: AudioBufferSourceNode | null = null
  private footstepTimer = 0
  private isWalking = false

  constructor() {
    // AudioContext is created on first user interaction
  }

  private ensureContext() {
    if (!this.ctx) {
      this.ctx = new AudioContext()
      this.masterGain = this.ctx.createGain()
      this.masterGain.connect(this.ctx.destination)
      this.updateVolume()
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume()
    }
  }

  updateVolume() {
    if (this.masterGain) {
      const vol = useGameStore.getState().settings.masterVolume
      this.masterGain.gain.setValueAtTime(vol, this.ctx!.currentTime)
    }
  }

  // Generate a short noise burst for footsteps
  private playFootstep() {
    this.ensureContext()
    if (!this.ctx || !this.masterGain) return

    const duration = 0.08 + Math.random() * 0.04
    const sampleRate = this.ctx.sampleRate
    const length = Math.floor(sampleRate * duration)
    const buffer = this.ctx.createBuffer(1, length, sampleRate)
    const data = buffer.getChannelData(0)

    // Filtered noise burst with lower, heavier pitch variation
    const pitch = 0.5 + Math.random() * 0.3
    for (let i = 0; i < length; i++) {
      const t = i / length
      // Envelope: sharp attack, quick decay
      const env = Math.exp(-t * 15)
      // Low-pass filtered noise
      const noise = (Math.random() * 2 - 1) * env
      data[i] = noise * 0.5 * Math.sin(t * pitch * 100) // Lower pitch sine
    }

    const source = this.ctx.createBufferSource()
    source.buffer = buffer

    // Bandpass filter for heavier thud
    const filter = this.ctx.createBiquadFilter()
    filter.type = 'lowpass' // Changed to lowpass for deeper sound
    filter.frequency.value = 300 + Math.random() * 150
    filter.Q.value = 1.0

    source.connect(filter)
    filter.connect(this.masterGain)
    source.start()
  }

  // Mechanical click for artifact ring rotation
  playClick() {
    this.ensureContext()
    if (!this.ctx || !this.masterGain) return

    const osc = this.ctx.createOscillator()
    const gain = this.ctx.createGain()

    osc.type = 'sine'
    osc.frequency.setValueAtTime(2200, this.ctx.currentTime)
    osc.frequency.exponentialRampToValueAtTime(800, this.ctx.currentTime + 0.03)

    gain.gain.setValueAtTime(0.15, this.ctx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.06)

    osc.connect(gain)
    gain.connect(this.masterGain)

    osc.start()
    osc.stop(this.ctx.currentTime + 0.06)

    // Secondary metallic ping
    const osc2 = this.ctx.createOscillator()
    const gain2 = this.ctx.createGain()

    osc2.type = 'triangle'
    osc2.frequency.setValueAtTime(4400, this.ctx.currentTime)
    osc2.frequency.exponentialRampToValueAtTime(1800, this.ctx.currentTime + 0.05)

    gain2.gain.setValueAtTime(0.08, this.ctx.currentTime)
    gain2.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.08)

    osc2.connect(gain2)
    gain2.connect(this.masterGain)

    osc2.start()
    osc2.stop(this.ctx.currentTime + 0.08)
  }

  // Start the low ambient room hum
  async startAmbient() {
    this.ensureContext()
    if (!this.ctx || !this.masterGain || this.ambientSource) return

    try {
      const response = await fetch('/audio/room-ambient.mp3')
      const arrayBuffer = await response.arrayBuffer()
      const audioBuffer = await this.ctx.decodeAudioData(arrayBuffer)
      
      this.ambientSource = this.ctx.createBufferSource()
      this.ambientSource.buffer = audioBuffer
      this.ambientSource.loop = true
      
      // Keep it slightly quiet so it's not overpowering
      const ambientGain = this.ctx.createGain()
      ambientGain.gain.value = 0.5
      
      this.ambientSource.connect(ambientGain)
      ambientGain.connect(this.masterGain)
      this.ambientSource.start()
    } catch (err) {
      console.error('Failed to load ambient audio:', err)
    }
  }

  stopAmbient() {
    if (this.ambientSource) {
      this.ambientSource.stop()
      this.ambientSource = null
    }
  }

  // Call this every frame from the animation loop
  updateWalking(isMoving: boolean, deltaMs: number) {
    if (isMoving && !this.isWalking) {
      this.isWalking = true
      this.footstepTimer = 0
    } else if (!isMoving) {
      this.isWalking = false
      this.footstepTimer = 0
      return
    }

    if (this.isWalking) {
      this.footstepTimer += deltaMs
      if (this.footstepTimer > 380) { // Footstep every ~380ms
        this.footstepTimer = 0
        this.playFootstep()
      }
    }
  }

  dispose() {
    this.stopAmbient()
    if (this.ctx) {
      this.ctx.close()
      this.ctx = null
    }
  }
}
