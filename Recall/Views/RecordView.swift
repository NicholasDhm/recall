import AVFoundation
import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingPipeline.self) private var pipeline
    @State private var recorder = AudioRecorder()
    @State private var live = LiveTranscriber()
    @State private var settings = AppSettings.shared
    @State private var permission = AudioRecorder.permission
    @State private var errorMessage: String?
    @State private var openedRecording: Recording?
    @State private var pendingID = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(DurationFormat.clock(recorder.elapsed))
                    .font(.system(size: 58, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("Tempo de gravação"))
                    .accessibilityValue(Text(DurationFormat.clock(recorder.elapsed)))

                LevelMeter(levels: recorder.levels, isActive: recorder.isRecording)
                    .frame(height: 64)

                transcript

                if permission == .denied {
                    deniedNotice
                } else {
                    recordButton
                }
            }
            .padding()
            .padding(.bottom, 28)
            .navigationTitle("Gravar")
            .sensoryFeedback(trigger: recorder.isRecording) { _, isRecording in
                isRecording ? .impact(weight: .heavy) : .success
            }
            .navigationDestination(item: $openedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .alert("Não foi possível gravar", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let reason = live.unavailableReason {
                        Label(reason, systemImage: "text.badge.xmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("A transcrição será feita depois da gravação.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if live.displayText.isEmpty {
                        Text(recorder.isRecording ? "Ouvindo…" : "A transcrição aparece aqui enquanto você fala.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(live.displayText)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: live.displayText) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var recordButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .frame(width: 96, height: 96)
                RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 38, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(
                        width: recorder.isRecording ? 40 : 78,
                        height: recorder.isRecording ? 40 : 78
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? Text("Parar gravação") : Text("Iniciar gravação"))
    }

    private var deniedNotice: some View {
        ContentUnavailableView {
            Label("Microfone bloqueado", systemImage: "mic.slash")
        } description: {
            Text("O Recall precisa do microfone para gravar. Libere o acesso nos Ajustes do iPhone.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes", destination: url)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggle() async {
        if recorder.isRecording {
            await finish()
        } else {
            await begin()
        }
    }

    private func begin() async {
        if AudioRecorder.permission == .undetermined {
            _ = await AudioRecorder.requestPermission()
        }
        permission = AudioRecorder.permission
        guard permission == .granted else { return }

        do {
            try recorder.start(id: pendingID)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if let buffers = recorder.bufferStream {
            await live.start(locale: settings.transcriptionLocale, buffers: buffers)
        }
    }

    private func finish() async {
        guard let finished = recorder.stop() else { return }
        let output = await live.finish()

        guard finished.duration >= 0.5 else {
            AudioStore.shared.delete(fileName: finished.fileName)
            pendingID = UUID()
            return
        }

        let recording = Recording(
            id: pendingID,
            title: Recording.defaultTitle(for: .now),
            duration: finished.duration,
            audioFileName: finished.fileName,
            localeIdentifier: settings.transcriptionLocaleIdentifier,
            source: .microphone
        )

        // The live pass already produced a transcript; skip straight to analysis.
        if let output, !output.text.isEmpty {
            recording.transcriptText = output.text
            recording.wordCount = output.wordCount
            recording.segments = output.segments.map {
                TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
            }
            recording.status = .transcribed
        }

        modelContext.insert(recording)
        try? modelContext.save()
        pendingID = UUID()
        pipeline.resume()
        openedRecording = recording
    }
}
