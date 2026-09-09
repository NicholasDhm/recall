import AVFoundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(Navigation.self) private var navigation
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var settings = AppSettings.shared
    @State private var path: [Recording] = []
    @State private var query = ""
    @State private var pendingDeletion: Recording?
    @State private var isImporting = false
    @State private var importError: String?

    private var filtered: [Recording] {
        var result = recordings
        if let tag = navigation.libraryTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        return query.isEmpty ? result : result.filter { $0.matches(query: query) }
    }

    private var groups: [(group: RecordingGroup, items: [Recording])] {
        RecordingGroup.bucket(filtered, date: \.createdAt)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if recordings.isEmpty {
                    emptyLibrary
                } else if filtered.isEmpty {
                    emptyResult
                } else {
                    timeline
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $query, prompt: Text("Buscar"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Importar áudio", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                    .buttonStyle(.glass)
                }
            }
            .navigationDestination(for: Recording.self) { RecordingDetailView(recording: $0) }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: AudioFormat.importableContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Excluir esta gravação?",
                isPresented: deletionBinding,
                titleVisibility: .visible
            ) {
                Button("Excluir", role: .destructive) {
                    if let pendingDeletion {
                        RecordingActions.delete(pendingDeletion, in: modelContext)
                    }
                    pendingDeletion = nil
                }
                Button("Cancelar", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("O áudio e a transcrição serão apagados deste iPhone.")
            }
            .alert("Não foi possível importar", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        List {
            if let tag = navigation.libraryTag {
                Button {
                    navigation.libraryTag = nil
                } label: {
                    HStack(spacing: 6) {
                        Text(tag)
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .buttonStyle(.glass)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: Metrics.gutter, bottom: 4, trailing: Metrics.gutter))
                .accessibilityLabel(Text("Remover o filtro da tag \(tag)"))
            }

            ForEach(groups, id: \.group) { section in
                Section {
                    ForEach(section.items) { recording in
                        Button {
                            path.append(recording)
                        } label: {
                            RecordingCard(recording: recording)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: Metrics.card, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .padding(.vertical, 4)
                        )
                        .listRowInsets(
                            EdgeInsets(top: 4, leading: Metrics.gutter, bottom: 4, trailing: Metrics.gutter)
                        )
                        .swipeActions(edge: .trailing) {
                            Button("Excluir", systemImage: "trash", role: .destructive) {
                                pendingDeletion = recording
                            }
                        }
                    }
                } header: {
                    Text(section.group.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.leading, 4)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .screenBackground()
    }

    // MARK: - Empty states

    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Nenhuma gravação")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text("Grave na aba Gravar ou traga um áudio que já existe.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Importar áudio", systemImage: "square.and.arrow.down") { isImporting = true }
                .buttonStyle(.glassProminent)
                .padding(.top, 4)
        }
        .padding(40)
    }

    private var emptyResult: some View {
        VStack(spacing: 10) {
            Text(navigation.libraryTag == nil ? "Nada encontrado" : "Nada com esta tag")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            if let tag = navigation.libraryTag {
                Button("Remover filtro “\(tag)”") { navigation.libraryTag = nil }
                    .buttonStyle(.glass)
            }
        }
        .padding(40)
    }

    // MARK: - Actions

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func importFiles(_ urls: [URL]) {
        let store = AudioStore.shared
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let id = UUID()
                let fileName = try store.importFile(from: url, id: id)
                let file = try? AVAudioFile(forReading: store.url(for: fileName))
                let duration = file.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
                modelContext.insert(
                    Recording(
                        id: id,
                        title: url.deletingPathExtension().lastPathComponent,
                        duration: duration,
                        audioFileName: fileName,
                        localeIdentifier: settings.transcriptionLocaleIdentifier,
                        source: .imported
                    )
                )
            } catch {
                importError = error.localizedDescription
            }
        }
        try? modelContext.save()
        pipeline.resume()
    }
}

struct RecordingCard: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.title)
                .font(.cardTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if recording.source == .imported {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption2)
                }
                Text(recording.createdAt, format: .dateTime.hour().minute())
                Text(verbatim: "·")
                Text(DurationFormat.clock(recording.duration))
                    .monospacedDigit()
                if let notice = recording.statusNotice {
                    Text(verbatim: "·")
                    Text(notice)
                }
            }
            .font(.meta)
            .foregroundStyle(recording.status == .failed ? Color.red : Color.secondary)

            if let summary = recording.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            if !recording.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recording.tags.prefix(3), id: \.self) { Chip(text: $0) }
                }
                .padding(.top, 2)
            }
        }
        .padding(4)
        .contentShape(Rectangle())
    }
}
