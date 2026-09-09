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
                Color.paper.ignoresSafeArea()

                VStack(spacing: 0) {
                    marker
                    LiveTranscript(live: live, isRecording: recorder.isRecording)
                    Spacer(minLength: 0)
                }

                controls
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $openedRecording) { RecordingDetailView(recording: $0) }
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

    private var marker: some View {
        HStack(spacing: 7) {
            if recorder.isRecording {
                Circle()
                    .fill(Color.ember)
                    .frame(width: 6, height: 6)
                    .opacity(pulse && !reduceMotion ? 0.25 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: pulse
                    )
                Marker(text: String(localized: "Gravando"))
            } else {
                Marker(text: Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)))
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if speechModel.needsDownload || speechModel.isInstalling {
                modelNotice
                Rule().padding(.horizontal, Metrics.gutter)
            }

            Waveform(recorder: recorder)
                .frame(height: recorder.isRecording ? 46 : 18)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 22)

            Text(recorder.isRecording ? DurationFormat.clock(recorder.elapsed) : " ")
                .font(.numeric(34))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: recorder.elapsed)
                .padding(.top, 14)

            if permission == .denied {
                deniedNotice
            } else {
                recordButton.padding(.top, 16)
            }
        }
        .padding(.bottom, 26)
        .animation(.smooth(duration: 0.35), value: recorder.isRecording)
    }

    private var modelNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcrição ao vivo indisponível")
                    .font(.uiLabel)
                    .foregroundStyle(Color.ink)
                Text(speechModel.isInstalling
                     ? String(localized: "Baixando a voz… \(Int(speechModel.progress * 100))%")
                     : String(localized: "Baixe a voz \(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier)) para ver o texto enquanto fala."))
                    .font(.uiMeta)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
            if speechModel.isInstalling {
                ProgressView().tint(Color.ember)
            } else {
                Button("Baixar") {
                    Task { await speechModel.install(for: settings.transcriptionLocale) }
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.ember)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
    }

    private var recordButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.ember.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                    .scaleEffect(recorder.isRecording && !reduceMotion && pulse ? 1.28 : 1)
                    .opacity(recorder.isRecording && !reduceMotion && pulse ? 0 : 1)
                    .animation(
                        reduceMotion || !recorder.isRecording
                            ? nil
                            : .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                        value: pulse
                    )

                Circle()
                    .stroke(Color.rule, lineWidth: 1)
                    .frame(width: 88, height: 88)

                RoundedRectangle(cornerRadius: recorder.isRecording ? 7 : 34, style: .continuous)
                    .fill(Color.ember)
                    .frame(
                        width: recorder.isRecording ? 30 : 68,
                        height: recorder.isRecording ? 30 : 68
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
                .font(.uiMeta)
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes", destination: url)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.ember)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, Metrics.gutter)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Actions

    private func toggle() async {
        if recorder.isRecording { await finish() } else { await begin() }
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

/// Kept separate so partial results invalidate only this subtree.
private struct LiveTranscript: View {
    let live: LiveTranscriber
    let isRecording: Bool

    private var isEmpty: Bool { live.finalizedText.isEmpty && live.volatileText.isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason = live.unavailableReason, isRecording {
                        // Surfaced rather than swallowed: a failed live pass would
                        // otherwise look identical to a microphone that heard nothing.
                        Text(reason)
                            .font(.uiMeta)
                            .foregroundStyle(Color.inkSoft)
                    }

                    if isEmpty {
                        Spacer(minLength: 0)
                        Text(isRecording
                             ? String(localized: "Ouvindo…")
                             : String(localized: "Toque e fale."))
                            .font(.reading)
                            .foregroundStyle(Color.inkFaint)
                            .frame(maxWidth: .infinity, alignment: isRecording ? .leading : .center)
                        Spacer(minLength: 0)
                    } else {
                        (Text(live.finalizedText).foregroundColor(Color.ink)
                            + Text(live.volatileText.isEmpty ? "" : " " + live.volatileText)
                                .foregroundColor(Color.inkFaint))
                            .font(.reading)
                            .lineSpacing(9)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, minHeight: isEmpty ? 340 : 0, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
            .onChange(of: live.finalizedText) { scroll(proxy) }
            .onChange(of: live.volatileText) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
