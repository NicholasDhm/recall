import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// The one place the recording format is defined: AAC in an `.m4a` container,
/// mono, 32 kbps, 16 kHz — small files, and the sample rate on-device speech wants.
enum AudioFormat {
    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1
    static let bitRate = 32_000
    static let fileExtension = "m4a"

    static var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVEncoderBitRateKey: bitRate
        ]
    }

    /// Uncompressed shape the tap converts into before the file encodes it.
    static var processing: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
    }

    /// File types accepted by the Library importer.
    static var importableContentTypes: [UTType] {
        var types: [UTType] = [.mpeg4Audio, .mp3, .wav]
        types += ["public.aac-audio", "com.apple.coreaudio-format"].compactMap(UTType.init(_:))
        return types
    }
}
