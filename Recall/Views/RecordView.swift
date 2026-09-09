import AVFoundation
import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var recorder = AudioRecorder()
    @State private var live = LiveTranscriber()
    @State private var settings = AppSettings.shared
    @State private var speechModel = SpeechModelState.shared
    @State private var permission = AudioRecorder.permission
    @State private var errorMessage: String?
    @State private var openedRecording: Recording?
    @State private var pendingID = UUID()
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                backdrop

                VStack(spacing: 0) {
                    statusBar
                    LiveTranscript(live: live, isRecording: recorder.isRecording)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.gutter)

                controls
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $openedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .task {
                await speechModel.refresh(for: settings.transcriptionLocale)
                #if DEBUG
                if LaunchOptions.autoRecord, !recorder.isRecording { await begin() }
                #endif
            }
            .sensoryFeedback(trigger: recorder.isRecording) { _, isRecording in
                isRecording ? .impact(weight: .heavy) : .success
            }
            .alert("Não foi possível gravar", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(recorder.isRecording ? 0.16 : 0), .clear],
            startPoint: .bottom,
            endPoint: .center
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: recorder.isRecording)
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulse && !reduceMotion ? 0.3 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: pulse
                    )
                Text("Gravando")
            } else {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
            }
            Spacer()
        }
        .font(.meta)
        .foregroundStyle(recorder.isRecording ? Color.primary : Color.secondary)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 18) {
            if speechModel.needsDownload || speechModel.isInstalling {
                modelBanner
            }

            VStack(spacing: 10) {
                Waveform(recorder: recorder)
                    .frame(height: recorder.isRecording ? 52 : 22)

                if recorder.isRecording {
                    Text(DurationFormat.clock(recorder.elapsed))
                        .font(.timer(40))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: recorder.elapsed)
                        .transition(.opacity.combined(with: .blurReplace))
                }
            }

            if permission == .denied {
                deniedNotice
            } else {
                recordButton
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 28)
        .animation(.smooth(duration: 0.35), value: recorder.isRecording)
    }

    private var modelBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Transcrição ao vivo indisponível")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(speechModel.isInstalling
                     ? "Baixando a voz \(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier))…"
                     : "Baixe a voz \(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier)) para ver o texto enquanto fala.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if speechModel.isInstalling {
                ProgressView(value: speechModel.progress)
                    .progressViewStyle(.circular)
            } else {
                Button("Baixar") {
                    Task { await speechModel.install(for: settings.transcriptionLocale) }
                }
                .buttonStyle(.glass)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.control, style: .continuous))
    }

    private var recordButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 92, height: 92)
                    .scaleEffect(recorder.isRecording && !reduceMotion && pulse ? 1.22 : 1)
                    .opacity(recorder.isRecording && !reduceMotion && pulse ? 0 : 1)
                    .animation(
                        reduceMotion || !recorder.isRecording
                            ? nil
                            : .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: pulse
                    )

                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 92, height: 92)

                RoundedRectangle(cornerRadius: recorder.isRecording ? 9 : 38, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(
                        width: recorder.isRecording ? 34 : 76,
                        height: recorder.isRecording ? 34 : 76
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.bouncy(duration: 0.4), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? Text("Parar gravação") : Text("Iniciar gravação"))
    }

    private var deniedNotice: some View {
        VStack(spacing: 10) {
            Text("O Recall precisa do microfone para gravar.")
                .font(.system(.subheadline, design: .rounded))
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes", destination: url)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.control, style: .continuous))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Actions

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
        pulse = true

        if let buffers = recorder.bufferStream {
            await live.start(locale: settings.transcriptionLocale, buffers: buffers)
        }
    }

    private func finish() async {
        pulse = false
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

/// Kept separate so partial transcription results invalidate only this subtree.
private struct LiveTranscript: View {
    let live: LiveTranscriber
    let isRecording: Bool

    /// Lets the idle placeholder centre itself in the space the scroll view was given.
    private var minHeight: CGFloat { live.finalizedText.isEmpty ? 380 : 0 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let reason = live.unavailableReason, isRecording {
                        // Surfaced rather than swallowed: without this a failed live pass
                        // looks identical to a microphone that heard nothing.
                        Label(reason, systemImage: "text.badge.xmark")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }

                    if live.finalizedText.isEmpty && live.volatileText.isEmpty {
                        Spacer(minLength: 0)
                        Text(placeholder)
                            .font(.transcript)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: isRecording ? .leading : .center)
                            .multilineTextAlignment(isRecording ? .leading : .center)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 0)
                    } else {
                        // Concatenated so the not-yet-final words flow inline, dimmed.
                        (Text(live.finalizedText).font(.transcript)
                            + Text(live.volatileText.isEmpty ? "" : " " + live.volatileText)
                                .font(.transcript)
                                .foregroundColor(.secondary))
                            .lineSpacing(6)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
            .onChange(of: live.finalizedText) { scroll(proxy) }
            .onChange(of: live.volatileText) { scroll(proxy) }
        }
    }

    private var placeholder: String {
        if isRecording {
            String(localized: "Ouvindo…")
        } else {
            String(localized: "Toque no botão e fale. O texto aparece aqui.")
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
