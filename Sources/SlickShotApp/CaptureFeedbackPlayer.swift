import AVFoundation
import Foundation

@MainActor
protocol CaptureFeedbackPlaying: AnyObject {
    func playCaptureCompleted()
    func playDropCompleted()
}

@MainActor
final class NullCaptureFeedbackPlayer: CaptureFeedbackPlaying {
    func playCaptureCompleted() {}
    func playDropCompleted() {}
}

@MainActor
final class CaptureFeedbackPlayer: CaptureFeedbackPlaying {
    private enum Event {
        case captureCompleted
        case dropCompleted
    }

    private var activePlayers: [AVAudioPlayer] = []

    func playCaptureCompleted() {
        play(.captureCompleted)
    }

    func playDropCompleted() {
        play(.dropCompleted)
    }

    private func play(_ event: Event) {
        let waveform = Self.makeWaveform(for: event)
        guard let player = try? AVAudioPlayer(data: waveform, fileTypeHint: AVFileType.wav.rawValue) else {
            return
        }

        activePlayers.removeAll { !$0.isPlaying }
        player.volume = event == .captureCompleted ? 0.42 : 0.26
        player.prepareToPlay()
        activePlayers.append(player)
        player.play()
    }

    private static func makeWaveform(for event: Event) -> Data {
        switch event {
        case .captureCompleted:
            return makeWAV(
                startFrequency: 810,
                endFrequency: 1_420,
                duration: 0.16,
                overtoneGain: 0.22,
                transientMix: 0.12,
                shimmerMix: 0.14
            )
        case .dropCompleted:
            return makeWAV(
                startFrequency: 1_260,
                endFrequency: 760,
                duration: 0.11,
                overtoneGain: 0.16,
                transientMix: 0.06,
                shimmerMix: 0.08
            )
        }
    }

    private static func makeWAV(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        overtoneGain: Double,
        transientMix: Double,
        shimmerMix: Double,
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
            let signal = (sin(theta) * 0.82)
                + (sin(overtoneTheta) * overtoneGain)
                + (sin(shimmerTheta) * shimmerMix)
                + (sin(transientTheta) * transientMix * transientEnvelope)
            let sample = Int16(max(-1, min(1, signal * envelope * 0.92)) * Double(Int16.max))
            append(sample)
        }

        return data
    }
}
