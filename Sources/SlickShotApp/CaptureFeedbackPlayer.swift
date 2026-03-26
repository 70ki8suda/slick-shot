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
        player.volume = event == .captureCompleted ? 0.48 : 0.32
        player.prepareToPlay()
        activePlayers.append(player)
        player.play()
    }

    private static func makeWaveform(for event: Event) -> Data {
        switch event {
        case .captureCompleted:
            return makeWAV(
                startFrequency: 760,
                endFrequency: 1_340,
                duration: 0.14,
                overtoneGain: 0.18
            )
        case .dropCompleted:
            return makeWAV(
                startFrequency: 1_120,
                endFrequency: 720,
                duration: 0.1,
                overtoneGain: 0.12
            )
        }
    }

    private static func makeWAV(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        overtoneGain: Double,
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
            let envelope = sin(.pi * progress)
            let easedProgress = progress * progress * (3 - (2 * progress))
            let frequency = startFrequency + ((endFrequency - startFrequency) * easedProgress)
            let theta = 2 * Double.pi * frequency * (Double(sampleIndex) / sampleRate)
            let overtoneTheta = theta * 1.84
            let signal = (sin(theta) * 0.84) + (sin(overtoneTheta) * overtoneGain)
            let sample = Int16(max(-1, min(1, signal * envelope * 0.92)) * Double(Int16.max))
            append(sample)
        }

        return data
    }
}
