import AVFoundation
import Foundation
import Observation

struct RecordingTick: Sendable {
    var level: Float
    var elapsed: TimeInterval
}

/// The audio thread hands a converted buffer over and never touches it again, so moving
/// it across an `AsyncStream` is safe even though `AVAudioPCMBuffer` is not `Sendable`.
struct CapturedAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

struct FinishedRecording: Sendable {
    var fileName: String
    var duration: TimeInterval
}

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            String(localized: "Acesso ao microfone negado.")
        case .engineUnavailable:
            String(localized: "Não foi possível iniciar o áudio.")
        }
    }
}

/// Audio-render-thread side of a recording. The tap block is the only caller between
/// `start` and `stop`, so the mutable state below needs no lock; the main actor reads
/// `frameCount` only after the tap has been removed.
private final class RecordingWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private(set) var frameCount: AVAudioFramePosition = 0

    init(url: URL, inputFormat: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: AudioFormat.settings)
        outputFormat = file.processingFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderError.engineUnavailable
        }
        self.converter = converter
    }

    /// Hands one buffer to the converter, exactly once. The converter calls this
    /// synchronously from inside `convert`, so no synchronisation is needed.
    private final class InputSource: @unchecked Sendable {
        private var pending: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) { pending = buffer }

        func next(_ packetCount: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            guard let pending else {
                status.pointee = .noDataNow
                return nil
            }
            self.pending = nil
            status.pointee = .haveData
            return pending
        }
    }

    /// Returns the converted buffer so the caller can also hand it to a transcriber,
    /// plus a 0...1 level for the meter.
    func append(_ input: AVAudioPCMBuffer) -> (buffer: CapturedAudioBuffer, level: Float)? {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        let source = InputSource(input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: source.next)

        guard status != .error, output.frameLength > 0 else { return nil }
        try? file.write(from: output)
        frameCount += AVAudioFramePosition(output.frameLength)
        return (CapturedAudioBuffer(buffer: output), Self.level(of: output))
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (decibels + 50) / 50))
    }
}

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Rolling window of levels for the meter; oldest first.
    private(set) var levels: [Float] = []

    static let levelWindow = 60

    private let engine = AVAudioEngine()
    private let store: AudioStore
    private var writer: RecordingWriter?
    private var fileName: String?
    private var tickTask: Task<Void, Never>?
    /// Set while recording so the transcription pipeline can consume the same buffers.
    private(set) var bufferStream: AsyncStream<CapturedAudioBuffer>?
    private var bufferContinuation: AsyncStream<CapturedAudioBuffer>.Continuation?

    init(store: AudioStore = .shared) {
        self.store = store
    }

    static var permission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(id: UUID) throws {
        guard !isRecording else { return }
        guard Self.permission == .granted else { throw AudioRecorderError.microphoneDenied }

        try store.createDirectoryIfNeeded()
        // The session must be configured first: until then the input node reports 0 Hz.
        try configureSession()

        let name = store.makeFileName(id: id)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw AudioRecorderError.engineUnavailable }

        let writer = try RecordingWriter(url: store.url(for: name), inputFormat: inputFormat)

        let (tickStream, tickContinuation) = AsyncStream<RecordingTick>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        let (buffers, bufferContinuation) = AsyncStream<CapturedAudioBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )
        let sampleRate = AudioFormat.sampleRate

        // Explicitly @Sendable: the block runs on the audio render thread, and an
        // inherited main-actor isolation would trap the executor check there.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            guard let converted = writer.append(buffer) else { return }
            bufferContinuation.yield(converted.buffer)
            tickContinuation.yield(
                RecordingTick(
                    level: converted.level,
                    elapsed: Double(writer.frameCount) / sampleRate
                )
            )
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            tickContinuation.finish()
            bufferContinuation.finish()
            store.delete(fileName: name)
            throw error
        }

        self.writer = writer
        self.fileName = name
        self.bufferStream = buffers
        self.bufferContinuation = bufferContinuation
        isRecording = true
        elapsed = 0
        levels = []

        tickTask = Task { [weak self] in
            for await tick in tickStream {
                guard let self else { return }
                self.apply(tick)
            }
        }
    }

    @discardableResult
    func stop() -> FinishedRecording? {
        guard isRecording, let writer, let fileName else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bufferContinuation?.finish()
        tickTask?.cancel()
        tickTask = nil

        let duration = Double(writer.frameCount) / AudioFormat.sampleRate
        // Releasing the writer closes the AVAudioFile, which finalises the m4a container.
        self.writer = nil
        self.fileName = nil
        self.bufferStream = nil
        self.bufferContinuation = nil
        isRecording = false
        elapsed = duration

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return FinishedRecording(fileName: fileName, duration: duration)
    }

    func cancel() {
        guard let finished = stop() else { return }
        store.delete(fileName: finished.fileName)
    }

    private func apply(_ tick: RecordingTick) {
        elapsed = tick.elapsed
        levels.append(tick.level)
        if levels.count > Self.levelWindow {
            levels.removeFirst(levels.count - Self.levelWindow)
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }
}
