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
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    header
                    player
                    analysis
                    transcript
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 48)
            }
            .paperBackground()
        }
        // Own chrome: the system bar would float white circles over the paper.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            .accessibilityLabel(Text("Voltar"))

            Spacer()

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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            .accessibilityLabel(Text("Mais ações"))
        }
        .padding(.top, 6)
        .padding(.bottom, 22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Título", text: $recording.title, axis: .vertical)
                .font(.displayMedium)
                .foregroundStyle(Color.ink)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .onSubmit { try? modelContext.save() }

            HStack(spacing: 5) {
                Text(recording.createdAt.formatted(date: .long, time: .shortened))
                Text(verbatim: "·")
                Text(DurationFormat.clock(recording.duration)).monospacedDigit()
                if recording.wordCount > 0 {
                    Text(verbatim: "·")
                    Text("\(recording.wordCount) palavras")
                }
            }
            .font(.uiMeta)
            .foregroundStyle(Color.inkSoft)

            if !recording.tags.isEmpty {
                FlowLayout {
                    ForEach(recording.tags, id: \.self) { Chip(text: $0) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private var player: some View {
        if let loadError {
            Text(loadError)
                .font(.uiMeta)
                .foregroundStyle(Color.inkSoft)
                .padding(.bottom, 26)
        } else {
            VStack(spacing: 14) {
                Scrubber(value: playback.currentTime, duration: max(playback.duration, 0.1)) {
                    playback.seek(to: $0)
                }

                HStack {
                    Text(DurationFormat.clock(playback.currentTime))
                    Spacer()
                    Text("−" + DurationFormat.clock(max(0, playback.duration - playback.currentTime)))
                }
                .font(.system(.caption2, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.inkFaint)

                HStack(spacing: 34) {
                    Button { playback.seek(to: playback.currentTime - 15) } label: {
                        Image(systemName: "gobackward.15").font(.system(size: 19))
                    }
                    .accessibilityLabel(Text("Voltar 15 segundos"))

                    Button(action: playback.toggle) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.ember)
                            .frame(width: 46, height: 46)
                    }
                    .accessibilityLabel(playback.isPlaying ? Text("Pausar") : Text("Reproduzir"))

                    Button { playback.seek(to: playback.currentTime + 15) } label: {
                        Image(systemName: "goforward.15").font(.system(size: 19))
                    }
                    .accessibilityLabel(Text("Avançar 15 segundos"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
            }
            .padding(.bottom, 30)
        }
    }

    @ViewBuilder
    private var analysis: some View {
        if !recording.transcriptText.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Rule()
                Marker(text: String(localized: "Resumo")).padding(.top, 4)

                if let summary = recording.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.reading)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(7)

                    if !recording.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Marker(text: String(localized: "Itens de ação")).padding(.top, 6)
                            ForEach(recording.actionItems, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .stroke(Color.ember, lineWidth: 1.2)
                                        .frame(width: 7, height: 7)
                                    Text(item)
                                        .font(.readingSmall)
                                        .foregroundStyle(Color.ink)
                                }
                            }
                        }
                    }
                } else if recording.status == .analyzing {
                    HStack(spacing: 9) {
                        ProgressView().tint(Color.ember)
                        Text("Analisando…").font(.uiMeta).foregroundStyle(Color.inkSoft)
                    }
                } else {
                    Text(unavailableReason)
                        .font(.uiMeta)
                        .foregroundStyle(Color.inkSoft)
                    if recording.status == .failed {
                        Button("Tentar de novo") { pipeline.retry(recording) }
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.ember)
                    }
                }
            }
            .padding(.bottom, 32)
        } else if let notice = recording.statusNotice {
            VStack(alignment: .leading, spacing: 10) {
                Rule()
                HStack(spacing: 10) {
                    if recording.status != .failed { ProgressView().tint(Color.ember) }
                    Text(notice).font(.uiMeta).foregroundStyle(Color.inkSoft)
                    Spacer(minLength: 0)
                    if recording.status == .failed {
                        Button("Tentar") { pipeline.retry(recording) }
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.ember)
                    }
                }
                .padding(.top, 12)
                if let progress = pipeline.downloadProgress, pipeline.activeRecordingID == recording.id {
                    ProgressView(value: progress).tint(Color.ember)
                }
            }
            .padding(.bottom, 30)
        }
    }

    private var unavailableReason: String {
        if let reason = TranscriptAnalyzer.availability.reason { return reason }
        if let stored = recording.failureReason, !stored.isEmpty { return stored }
        return String(localized: "Ainda sem resumo para esta gravação.")
    }

    @ViewBuilder
    private var transcript: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rule()
                Marker(text: String(localized: "Transcrição"))
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ForEach(segments) { segment in
                    Button { playback.seek(to: segment.start) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(DurationFormat.clock(segment.start))
                                .font(.system(.caption2, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(isCurrent(segment) ? Color.ember : Color.inkFaint)
                                .frame(width: 38, alignment: .leading)
                            Text(segment.text)
                                .font(.reading)
                                .lineSpacing(7)
                                .foregroundStyle(isCurrent(segment) ? Color.ink : Color.ink.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .leading) {
                            if isCurrent(segment) {
                                Rectangle()
                                    .fill(Color.ember)
                                    .frame(width: 2)
                                    .offset(x: -12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Toque para reproduzir a partir deste trecho"))
                }
            }
        } else if !recording.transcriptText.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Rule()
                Marker(text: String(localized: "Transcrição")).padding(.top, 4)
                Text(recording.transcriptText)
                    .font(.reading)
                    .lineSpacing(7)
                    .foregroundStyle(Color.ink)
                    .textSelection(.enabled)
            }
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

/// Hairline transport bar. A stock `Slider` gives a screen away as a form.
private struct Scrubber: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(value / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.rule).frame(height: 3)
                Capsule().fill(Color.ember).frame(width: proxy.size.width * fraction, height: 3)
                Circle()
                    .fill(Color.ember)
                    .frame(width: 11, height: 11)
                    .offset(x: proxy.size.width * fraction - 5.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    onSeek(min(max(gesture.location.x / proxy.size.width, 0), 1) * duration)
                }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(Text("Posição da reprodução"))
        .accessibilityValue(Text(DurationFormat.clock(value)))
        .accessibilityAdjustableAction { direction in
            onSeek(value + (direction == .increment ? 15 : -15))
        }
    }
}
