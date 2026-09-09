import AVFoundation
import Foundation

/// Resamples PCM buffers between two formats, keeping the converter's internal state
/// across calls. Callers hand a buffer over and never touch it again, which is what
/// makes this safe to use from the audio render thread.
final class AudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        let source = SingleBufferSource(input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: source.next)
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Hands one buffer to the converter, exactly once. `convert` calls this
    /// synchronously, so no synchronisation is needed.
    private final class SingleBufferSource: @unchecked Sendable {
        private var pending: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) { pending = buffer }

        func next(
            _ packetCount: AVAudioPacketCount,
            _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>
        ) -> AVAudioBuffer? {
            guard let pending else {
                status.pointee = .noDataNow
                return nil
            }
            self.pending = nil
            status.pointee = .haveData
            return pending
        }
    }
}
