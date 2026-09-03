import AVFoundation
import Foundation

/// Mutable state owned by the audio render thread.
///
/// Everything here is touched only from inside the render block while the
/// engine is running, or from the main thread while it is stopped — never both
/// at once — so no locking is needed on the real-time path.
final class AudioState: @unchecked Sendable {
    var n: Double = 0            // sample counter
    var fadeN: Double = 0        // samples since start, for the fade-in
    var lastPhaseIdx: Int = -1
    var strikeT: Double = -1000  // when the bowl was last struck
    var strikeF: Double = 392
    var lp: Double = 0           // one-pole lowpass state for the air layer
    var rng: UInt64 = 0x9E3779B97F4A7C15
}

/// One sample of the soundscape, advancing `st` by a frame.
///
/// Kept as a free function rather than buried in the render block so it can be
/// rendered offline and measured — the audio is generated, so this is the only
/// way to check it is actually producing sound and staying in range.
@inline(__always)
func renderSoundscapeSample(st: AudioState, sampleRate sr: Double,
                            cycle cyc: Double, root: Double) -> Double {
    let t = st.n / sr
    st.n += 1
    st.fadeN += 1

    let pos = t.truncatingRemainder(dividingBy: cyc)
    let b = (1 - cos(2 * .pi * pos / cyc)) / 2      // same curve as the visuals

    // Strike the bowl whenever the breath turns.
    let idx = pos < cyc / 2 ? 0 : 1
    if idx != st.lastPhaseIdx {
        st.lastPhaseIdx = idx
        st.strikeT = t
        // Inhale opens on the fifth, exhale settles onto the root.
        st.strikeF = (idx == 0) ? 392.0 : 261.63
    }

    // — Drone: a slow, low bed that never quite sits still. It lifts a little
    //   with the breath too, so the whole bed moves rather than just the pad
    //   riding over a flat floor.
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

    let fade = min(1.0, st.fadeN / (sr * 2.5))
    return tanh((drone + pad + bell + air) * 1.15) * 0.95 * fade
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

    // MARK: Graph

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

        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, ablPtr -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)

            for frame in 0..<Int(frameCount) {
                let sample = Float(renderSoundscapeSample(st: st, sampleRate: sr,
                                                          cycle: cyc, root: root))
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

    // MARK: Transport

    /// Starts (or resumes) the bed at a given point in the breath. The counters
    /// are only rewound while the engine is stopped, so the render thread never
    /// sees them change underneath it.
    func start(atElapsed elapsed: Double) {
        configure()
        guard configured else { return }

        state.n = max(0, elapsed) * sampleRate
        state.fadeN = 0
        state.lp = 0
        let pos = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        state.lastPhaseIdx = pos < cycle / 2 ? 0 : 1   // avoid a stray strike on resume
        state.strikeT = -1000

        engine.prepare()
        try? engine.start()
    }

    func pause() {
        guard configured else { return }
        engine.pause()
    }

    /// Mute rides the mixer's own volume, which AVAudioEngine ramps for us — so
    /// it is click-free and safe to set from the main thread while rendering.
    func setMuted(_ muted: Bool) {
        configure()
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }
}
