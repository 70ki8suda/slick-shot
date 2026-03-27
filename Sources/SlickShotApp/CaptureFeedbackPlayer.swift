import AVFoundation
import Foundation

@MainActor
protocol CaptureFeedbackPlaying: AnyObject {
    func playCaptureCompleted()
    func playDropCompleted()
    func playReticleReveal()
}

@MainActor
final class NullCaptureFeedbackPlayer: CaptureFeedbackPlaying {
    func playCaptureCompleted() {}
    func playDropCompleted() {}
    func playReticleReveal() {}
}

@MainActor
final class CaptureFeedbackPlayer: CaptureFeedbackPlaying {
    private enum Event {
        case captureCompleted
        case dropCompleted
        case reticleReveal
    }

    private var activePlayers: [AVAudioPlayer] = []

    func playCaptureCompleted() {
        play(.captureCompleted)
    }

    func playDropCompleted() {
        play(.dropCompleted)
    }

    func playReticleReveal() {
        play(.reticleReveal)
    }

    private func play(_ event: Event) {
        let waveform = Self.makeWaveform(for: event)
        guard let player = try? AVAudioPlayer(data: waveform, fileTypeHint: AVFileType.wav.rawValue) else {
            return
        }

        activePlayers.removeAll { !$0.isPlaying }
        switch event {
        case .captureCompleted:
            player.volume = 0.42
        case .dropCompleted:
            player.volume = 0.26
        case .reticleReveal:
            player.volume = 0.045
        }
        player.prepareToPlay()
        activePlayers.append(player)
        player.play()
    }

    private static func makeWaveform(for event: Event) -> Data {
        switch event {
        case .captureCompleted:
            return makeWAV(
                startFrequency: 760,
                endFrequency: 980,
                duration: 0.11,
                overtoneGain: 0.24,
                transientMix: 0.34,
                shimmerMix: 0.01,
                mechanicalPulseMix: 0.24,
                pitchSnapMix: 0.16
            )
        case .dropCompleted:
            return makeWAV(
                startFrequency: 1_260,
                endFrequency: 760,
                duration: 0.11,
                overtoneGain: 0.16,
                transientMix: 0.06,
                shimmerMix: 0.08,
                mechanicalPulseMix: 0.04,
                pitchSnapMix: 0.05
            )
        case .reticleReveal:
            return makeReticleRevealWAV()
        }
    }

    private static func makeReticleRevealWAV(sampleRate: Double = 44_100) -> Data {
        let duration = 0.25
        let frameCount = max(1, Int(sampleRate * duration))
        let bytesPerSample = MemoryLayout<Int16>.size
        let channelCount = 1
        let byteRate = Int(sampleRate) * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample
        let dataSize = frameCount * channelCount * bytesPerSample
        var data = Data(capacity: 44 + dataSize)

        func append<T>(_ value: T) {
            var mutableValue = value
            withUnsafeBytes(of: &mutableValue) { data.append(contentsOf: $0) }
        }

        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channelCount))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(16))
        data.append("data".data(using: .ascii)!)
        append(UInt32(dataSize))

        for sampleIndex in 0..<frameCount {
            let progress = Double(sampleIndex) / Double(max(frameCount - 1, 1))
            let eased = progress * progress * (3 - (2 * progress))
            let baseFrequency = 500 + (120 * eased)
            let theta = 2 * Double.pi * baseFrequency * (Double(sampleIndex) / sampleRate)
            let overtoneTheta = theta * 1.72
            let airTheta = theta * 2.45
            let flutter = sin(2 * Double.pi * 7.2 * (Double(sampleIndex) / sampleRate))
            let flutterGain = 1 + (flutter * 0.02)
            let onset = min(1, progress / 0.11)
            let release = min(1, (1 - progress) / 0.28)
            let envelope = pow(min(onset, release), 1.15)
            let signal = (sin(theta) * 0.56 * flutterGain)
                + (sin(overtoneTheta) * 0.08)
                + (sin(airTheta) * 0.02)
            let sample = Int16(max(-1, min(1, signal * envelope * 0.32)) * Double(Int16.max))
            append(sample)
        }

        return data
    }

    private static func makeWAV(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        overtoneGain: Double,
        transientMix: Double,
        shimmerMix: Double,
        mechanicalPulseMix: Double,
        pitchSnapMix: Double,
        sampleRate: Double = 44_100
    ) -> Data {
        let frameCount = max(1, Int(sampleRate * duration))
        let bytesPerSample = MemoryLayout<Int16>.size
        let channelCount = 1
        let byteRate = Int(sampleRate) * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample
        let dataSize = frameCount * channelCount * bytesPerSample
        var data = Data(capacity: 44 + dataSize)

        func append<T>(_ value: T) {
            var mutableValue = value
            withUnsafeBytes(of: &mutableValue) { data.append(contentsOf: $0) }
        }

        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channelCount))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(16))
        data.append("data".data(using: .ascii)!)
        append(UInt32(dataSize))

        for sampleIndex in 0..<frameCount {
            let progress = Double(sampleIndex) / Double(max(frameCount - 1, 1))
            let envelope = pow(sin(.pi * progress), 1.35)
            let easedProgress = progress * progress * (3 - (2 * progress))
            let frequency = startFrequency + ((endFrequency - startFrequency) * easedProgress)
            let theta = 2 * Double.pi * frequency * (Double(sampleIndex) / sampleRate)
            let overtoneTheta = theta * 1.84
            let shimmerTheta = theta * 2.76
            let transientEnvelope = exp(-14 * progress)
            let transientTheta = 2 * Double.pi * 2_800 * (Double(sampleIndex) / sampleRate)
            let pulseTheta = theta * 0.5
            let pulseWave = sin(pulseTheta) >= 0 ? 1.0 : -1.0
            let pitchSnapEnvelope = exp(-11 * progress)
            let pitchSnapTheta = 2 * Double.pi * (frequency * 1.48) * (Double(sampleIndex) / sampleRate)
            let signal = (sin(theta) * 0.82)
                + (sin(overtoneTheta) * overtoneGain)
                + (sin(shimmerTheta) * shimmerMix)
                + (sin(transientTheta) * transientMix * transientEnvelope)
                + (pulseWave * mechanicalPulseMix * 0.32)
                + (sin(pitchSnapTheta) * pitchSnapMix * pitchSnapEnvelope)
            let sample = Int16(max(-1, min(1, signal * envelope * 0.92)) * Double(Int16.max))
            append(sample)
        }

        return data
    }
}
