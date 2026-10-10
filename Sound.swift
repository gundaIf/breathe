import AVFoundation
import Foundation

/// State for the audio render thread.
///
/// `targetRate` and `muteTarget` are written from the main thread and read on
/// the render thread. Each is a single aligned word, the conventional way to
/// pass a control value into a real-time audio callback without taking a lock;
/// the render side smooths whatever it reads, so a value landing a buffer late
/// is inaudible. Everything else is touched only on the render thread, or on the
/// main thread while the engine is stopped.
final class AudioState: @unchecked Sendable {
    var targetRate: Double = 1
    var muteTarget: Double = 1

    var n: Double = 0            // samples rendered: real time, drives pitch
    var tb: Double = 0           // breath time: slows and stops with the glide
    var glide = Glide(0)
    var muteGain: Double = 1
    var fadeN: Double = 0
    var lastPhaseIdx: Int = -1
    var strikeT: Double = -1000  // real time of the last bowl strike
    var strikeF: Double = 392
    var lp: Double = 0
    var rng: UInt64 = 0x9E3779B97F4A7C15

    func reset() {
        n = 0; tb = 0; glide = Glide(0)
        fadeN = 0; lastPhaseIdx = -1; strikeT = -1000; lp = 0
        muteGain = muteTarget
    }
}

/// One sample of the soundscape, advancing `st` by a frame.
///
/// Two clocks run here. Oscillators follow real time, so pitch never bends.
/// The breath — the pad's swell and the bowl strikes — follows `tb`, which
/// glides to a stop on pause along the same curve as the visuals.
///
/// A free function rather than a closure so it can be rendered offline and
/// measured; the sound is generated, so that is the only way to check it.
@inline(__always)
func renderSoundscapeSample(st: AudioState, sampleRate sr: Double,
                            cycle cyc: Double, root: Double,
                            muteCoef: Double) -> Double {
    let dt = 1 / sr
    let t = st.n * dt
    st.n += 1
    st.fadeN += 1

    st.tb += st.glide.step(dt, toward: st.targetRate)
    let rate = max(0, min(1, st.glide.r))
    st.muteGain += (st.muteTarget - st.muteGain) * muteCoef

    let pos = st.tb.truncatingRemainder(dividingBy: cyc)
    let b = (1 - cos(2 * .pi * pos / cyc)) / 2      // same curve as the visuals

    // Strike the bowl whenever the breath turns.
    let idx = pos < cyc / 2 ? 0 : 1
    if idx != st.lastPhaseIdx {
        st.lastPhaseIdx = idx
        st.strikeT = t
        // Inhale opens on the fifth, exhale settles onto the root.
        st.strikeF = (idx == 0) ? 392.0 : 261.63
    }

    // — Drone: a slow, low bed that lifts a little with the breath.
    let slow = sin(2 * .pi * 0.035 * t)
    let droneEnv = (0.86 + 0.14 * sin(2 * .pi * 0.05 * t)) * (0.80 + 0.20 * b)
    let drone = (0.070 * sin(2 * .pi * root * t)
               + 0.036 * sin(2 * .pi * root * 2 * t + 0.4 * slow)
               + 0.022 * sin(2 * .pi * root * 3 * t)) * droneEnv

    // — Pad: swells with the inhale, recedes with the exhale.
    let bb = pow(b, 1.15)
    let pad = bb * (0.082 * sin(2 * .pi * root * 4 * t)
                  + 0.055 * sin(2 * .pi * root * 6 * t)
                  + 0.032 * sin(2 * .pi * root * 4.5 * t))

    // — Singing bowl: inharmonic partials, each decaying at its own rate.
    //   Phase is measured from the strike, so it always starts at zero — no click.
    var bell = 0.0
    let since = t - st.strikeT
    if since >= 0 && since < 10 {
        let f = st.strikeF
        bell = 0.070 * sin(2 * .pi * f * since)        * exp(-since * 0.80)
             + 0.034 * sin(2 * .pi * f * 2.01 * since) * exp(-since * 1.55)
             + 0.019 * sin(2 * .pi * f * 2.99 * since) * exp(-since * 2.40)
             + 0.011 * sin(2 * .pi * f * 4.16 * since) * exp(-since * 3.60)
    }

    // — Air: xorshift noise through a one-pole lowpass, breathing with the pad.
    var x = st.rng
    x ^= x << 13; x ^= x >> 7; x ^= x << 17
    st.rng = x
    let white = Double(Int32(truncatingIfNeeded: x)) / Double(Int32.max)
    st.lp += 0.02 * (white - st.lp)
    let air = st.lp * 0.030 * (0.35 + 0.65 * b)

    // As the breath slows to rest the sound settles with it, then returns as
    // the breath picks back up.
    let presence = rate * rate * (3 - 2 * rate)
    let fade = min(1.0, st.fadeN / (sr * 2.5))
    return tanh((drone + pad + bell + air) * 1.15) * 0.95 * fade * presence * st.muteGain
}

/// A generated zen soundscape, locked to the same 12-second breath as the
/// visuals: a low drone bed, a pad that swells on the inhale, a singing bowl
/// struck at each turn, and a whisper of filtered air.
///
/// Nothing is sampled from disk — it is all synthesised, so the app stays tiny.
final class Soundscape {
    static let shared = Soundscape()

    private let engine = AVAudioEngine()
    private let state = AudioState()
    private var sampleRate: Double = 44100
    private var configured = false

    private let cycle: Double = 12
    private let f0: Double = 98        // G2 — the root of the whole bed

    private init() {}

    private func configure() {
        guard !configured else { return }

        let out = engine.outputNode
        let outFormat = out.inputFormat(forBus: 0)
        sampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44100

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                      channels: 2) else { return }

        let st = state
        let sr = sampleRate
        let cyc = cycle
        let root = f0
        let muteCoef = 1 - exp(-1 / (0.12 * sr))     // ~120 ms mute ramp

        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, ablPtr -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            for frame in 0..<Int(frameCount) {
                let sample = Float(renderSoundscapeSample(st: st, sampleRate: sr,
                                                          cycle: cyc, root: root,
                                                          muteCoef: muteCoef))
                for buffer in abl {
                    let p = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < p.count { p[frame] = sample }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        configured = true
    }

    /// Starts the bed from rest. Like the visuals, it eases into motion.
    func begin() {
        configure()
        guard configured else { return }
        state.targetRate = 1
        state.reset()
        engine.prepare()
        try? engine.start()
    }

    /// Glides the breath to rest or back to motion. The engine keeps running
    /// through the glide so the sound can settle rather than cut off.
    func setRunning(_ running: Bool) {
        guard configured else { return }
        if running && !engine.isRunning { try? engine.start() }
        state.targetRate = running ? 1 : 0
    }

    /// Once a pause has fully settled there is nothing left to hear, so stop
    /// rendering. State is kept, and `setRunning(true)` picks up where it left.
    func suspend() {
        guard configured, state.targetRate == 0 else { return }
        engine.pause()
    }

    func stop() {
        guard configured else { return }
        engine.pause()
    }

    /// Mute is a gain ramp inside the render loop, so it never clicks.
    func setMuted(_ muted: Bool) {
        state.muteTarget = muted ? 0 : 1
    }
}
