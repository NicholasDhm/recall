import AVFoundation
import Foundation
import Testing

@testable import Recall

@Suite("Audio format")
struct AudioFormatTests {
    @Test("Recording settings are AAC mono 32 kbps at 16 kHz")
    func settings() {
        let settings = AudioFormat.settings
        #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(settings[AVSampleRateKey] as? Double == 16_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVEncoderBitRateKey] as? Int == 32_000)
        #expect(AudioFormat.fileExtension == "m4a")
    }

    @Test("A written file round-trips as mono 16 kHz and its duration matches the frames written")
    func writtenFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(AudioFormat.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = 2.0
        let frames = AVAudioFrameCount(AudioFormat.sampleRate * seconds)

        do {
            let file = try AVAudioFile(forWriting: url, settings: AudioFormat.settings)
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
            )
            buffer.frameLength = frames
            // A quiet tone rather than pure silence, so the encoder writes real packets.
            let samples = try #require(buffer.floatChannelData?[0])
            for index in 0..<Int(frames) {
                samples[index] = 0.2 * sin(2 * .pi * 440 * Float(index) / Float(AudioFormat.sampleRate))
            }
            try file.write(from: buffer)
        }

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        let readBack = try AVAudioFile(forReading: url)
        #expect(readBack.fileFormat.sampleRate == AudioFormat.sampleRate)
        #expect(readBack.fileFormat.channelCount == AudioFormat.channelCount)

        // AAC adds encoder priming, so the decoded length is close to, not exactly, the input.
        let duration = Double(readBack.length) / readBack.fileFormat.sampleRate
        #expect(abs(duration - seconds) < 0.2)
    }

    @Test("Duration is derived from frames written at the recording sample rate")
    func durationFromFrameCount() {
        let frames: AVAudioFramePosition = 48_000
        #expect(Double(frames) / AudioFormat.sampleRate == 3.0)
    }
}
