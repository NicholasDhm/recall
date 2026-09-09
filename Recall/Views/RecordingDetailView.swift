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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                player
                analysis
                transcript
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: recording.markdownExport, preview: SharePreview(recording.title)) {
                        Label("Compartilhar markdown", systemImage: "square.and.arrow.up")
                    }
                    if !recording.transcriptText.isEmpty {
                        Button("Reanalisar", systemImage: "sparkles") {
                            pipeline.reanalyze(recording)
                        }
                        .disabled(TranscriptAnalyzer.availability != .available)
                    }
                    Divider()
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Mais ações"))
            }
        }
        .task { load() }
        .onDisappear {
            playback.stop()
            try? modelContext.save()
        }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: $recording.title, axis: .vertical)
                .font(.system(.title, design: .rounded, weight: .bold))
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .onSubmit { try? modelContext.save() }

            HStack(spacing: 6) {
                if recording.source == .imported {
                    Image(systemName: "square.and.arrow.down").font(.caption2)
                }
                Text(recording.createdAt.formatted(date: .long, time: .shortened))
                Text(verbatim: "·")
                Text(DurationFormat.clock(recording.duration)).monospacedDigit()
                if recording.wordCount > 0 {
                    Text(verbatim: "·")
                    Text("\(recording.wordCount) palavras")
                }
            }
            .font(.meta)
            .foregroundStyle(.secondary)

            if !recording.tags.isEmpty {
                FlowLayout {
                    ForEach(recording.tags, id: \.self) { Chip(text: $0) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
        } else {
            VStack(spacing: 12) {
                Scrubber(
                    value: playback.currentTime,
                    duration: max(playback.duration, 0.1)
                ) { playback.seek(to: $0) }

                HStack {
                    Text(DurationFormat.clock(playback.currentTime))
                    Spacer()
                    Text("−" + DurationFormat.clock(max(0, playback.duration - playback.currentTime)))
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

                HStack(spacing: 36) {
                    Button {
                        playback.seek(to: playback.currentTime - 15)
                    } label: {
                        Image(systemName: "gobackward.15").font(.title3)
                    }
                    .accessibilityLabel(Text("Voltar 15 segundos"))

                    Button(action: playback.toggle) {
                        ZStack {
                            Circle().fill(Color.accentColor).frame(width: 60, height: 60)
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: playback.isPlaying ? 0 : 2)
                        }
                    }
                    .accessibilityLabel(playback.isPlaying ? Text("Pausar") : Text("Reproduzir"))

                    Button {
                        playback.seek(to: playback.currentTime + 15)
                    } label: {
                        Image(systemName: "goforward.15").font(.title3)
                    }
                    .accessibilityLabel(Text("Avançar 15 segundos"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .padding(.top, 2)
            }
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.card, style: .continuous))
        }
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysis: some View {
        if !recording.transcriptText.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Resumo", systemImage: "sparkles")
                    .font(.cardTitle)
                    .foregroundStyle(Color.accentColor)

                if let summary = recording.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(.body, design: .default))
                        .lineSpacing(3)

                    if !recording.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Itens de ação")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(recording.actionItems, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                    Text(item).font(.system(.callout, design: .default))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                } else if recording.status == .analyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Analisando…").foregroundStyle(.secondary)
                    }
                    .font(.system(.callout, design: .rounded))
                } else {
                    Text(unavailableReason)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)

                    if recording.status == .failed {
                        Button("Tentar de novo", systemImage: "arrow.clockwise") {
                            pipeline.retry(recording)
                        }
                        .buttonStyle(.glass)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: 18)
        } else if let notice = recording.statusNotice {
            HStack(spacing: 10) {
                if recording.status != .failed { ProgressView() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice).font(.system(.callout, design: .rounded, weight: .medium))
                    if let progress = pipeline.downloadProgress, pipeline.activeRecordingID == recording.id {
                        ProgressView(value: progress).font(.caption)
                    }
                }
                Spacer(minLength: 0)
                if recording.status == .failed {
                    Button("Tentar") { pipeline.retry(recording) }
                        .buttonStyle(.glass)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
            }
            .surfaceCard(padding: 16)
        }
    }

    private var unavailableReason: String {
        if let reason = TranscriptAnalyzer.availability.reason { return reason }
        if let stored = recording.failureReason, !stored.isEmpty { return stored }
        return String(localized: "Ainda sem resumo para esta gravação.")
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcrição")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .padding(.bottom, 6)

                ForEach(segments) { segment in
                    Button {
                        playback.seek(to: segment.start)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(DurationFormat.clock(segment.start))
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(isCurrent(segment) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                .frame(width: 44, alignment: .leading)
                            Text(segment.text)
                                .font(.system(.body, design: .default))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isCurrent(segment) ? Color.accentColor.opacity(0.12) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Toque para reproduzir a partir deste trecho"))
                }
            }
        } else if !recording.transcriptText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcrição")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(recording.transcriptText)
                    .font(.system(.body, design: .default))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: 18)
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

/// Custom transport bar — the stock `Slider` is the giveaway that a screen is a form.
private struct Scrubber: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(value / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * fraction, height: 6)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: proxy.size.width * fraction - 7)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    onSeek(min(max(gesture.location.x / proxy.size.width, 0), 1) * duration)
                }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel(Text("Posição da reprodução"))
        .accessibilityValue(Text(DurationFormat.clock(value)))
        .accessibilityAdjustableAction { direction in
            onSeek(value + (direction == .increment ? 15 : -15))
        }
    }
}
