import SwiftData
import SwiftUI

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var playback = AudioPlayback()
    @State private var confirmingDelete = false
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                player
            }

            Section("Detalhes") {
                LabeledContent("Data", value: recording.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("Duração", value: DurationFormat.clock(recording.duration))
                LabeledContent("Origem", value: recording.source == .microphone ? "Microfone" : "Importado")
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

    private func load() {
        do {
            try playback.load(url: AudioStore.shared.url(for: recording.audioFileName))
            loadError = nil
        } catch {
            loadError = String(localized: "O arquivo de áudio não foi encontrado.")
        }
    }
}
