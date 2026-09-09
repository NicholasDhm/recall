import SwiftData
import SwiftUI

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss
    @State private var playback = AudioPlayback()
    @State private var confirmingDelete = false
    @State private var loadError: String?

    private var segments: [TranscriptSegment] {
        recording.segments.sorted { $0.start < $1.start }
    }

    var body: some View {
        List {
            Section { player }

            if let notice = recording.statusNotice {
                Section { statusRow(notice) }
            }

            transcriptSection

            Section("Detalhes") {
                LabeledContent("Data", value: recording.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("Duração", value: DurationFormat.clock(recording.duration))
                LabeledContent("Origem", value: recording.source == .microphone ? "Microfone" : "Importado")
                if recording.wordCount > 0 {
                    LabeledContent("Palavras", value: recording.wordCount.formatted())
                }
            }

            Section {
                Button("Excluir gravação", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onDisappear { playback.stop() }
        .confirmationDialog(
            "Excluir esta gravação?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                playback.stop()
                RecordingActions.delete(recording, in: modelContext)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O áudio e a transcrição serão apagados deste iPhone.")
        }
    }

    @ViewBuilder
    private func statusRow(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice, systemImage: recording.status == .failed ? "exclamationmark.triangle" : "clock")
                .foregroundStyle(recording.status == .failed ? .primary : .secondary)

            if let progress = pipeline.downloadProgress, pipeline.activeRecordingID == recording.id {
                ProgressView(value: progress) {
                    Text("Baixando o modelo de fala")
                }
                .font(.caption)
            }

            if recording.status == .failed {
                Button("Tentar de novo", systemImage: "arrow.clockwise") {
                    pipeline.retry(recording)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if !segments.isEmpty {
            Section("Transcrição") {
                ForEach(segments) { segment in
                    Button {
                        playback.seek(to: segment.start)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(DurationFormat.clock(segment.start))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(segment.text)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isCurrent(segment) ? Color.accentColor.opacity(0.14) : nil)
                    .accessibilityHint(Text("Toque para reproduzir a partir deste trecho"))
                }
            }
        } else if !recording.transcriptText.isEmpty {
            Section("Transcrição") {
                Text(recording.transcriptText).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var player: some View {
        if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 0.1)
                )
                .accessibilityLabel(Text("Posição da reprodução"))

                HStack {
                    Text(DurationFormat.clock(playback.currentTime))
                    Spacer()
                    Text(DurationFormat.clock(playback.duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                HStack(spacing: 32) {
                    Button {
                        playback.seek(to: playback.currentTime - 15)
                    } label: {
                        Image(systemName: "gobackward.15").font(.title2)
                    }
                    .accessibilityLabel(Text("Voltar 15 segundos"))

                    Button(action: playback.toggle) {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }
                    .accessibilityLabel(playback.isPlaying ? Text("Pausar") : Text("Reproduzir"))

                    Button {
                        playback.seek(to: playback.currentTime + 15)
                    } label: {
                        Image(systemName: "goforward.15").font(.title2)
                    }
                    .accessibilityLabel(Text("Avançar 15 segundos"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private func isCurrent(_ segment: TranscriptSegment) -> Bool {
        playback.isPlaying && playback.currentTime >= segment.start && playback.currentTime < segment.end
    }

    private func load() {
        do {
            try playback.load(url: AudioStore.shared.url(for: recording.audioFileName))
            loadError = nil
        } catch {
            loadError = String(localized: "O arquivo de áudio não foi encontrado.")
        }
    }
}
