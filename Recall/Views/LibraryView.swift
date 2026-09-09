import AVFoundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(Navigation.self) private var navigation
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var settings = AppSettings.shared
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

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhuma gravação", systemImage: "waveform")
                    } description: {
                        Text("Grave na aba Gravar ou importe um arquivo de áudio.")
                    } actions: {
                        Button("Importar áudio", systemImage: "square.and.arrow.down") {
                            isImporting = true
                        }
                    }
                } else if filtered.isEmpty {
                    emptyResult
                } else {
                    VStack(spacing: 0) {
                        tagFilterBar
                        list
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $query, prompt: Text("Buscar por título, transcrição ou tag"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Importar áudio", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                }
            }
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
            .alert("Não foi possível importar", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
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
        }
    }

    @ViewBuilder
    private var emptyResult: some View {
        if let tag = navigation.libraryTag {
            ContentUnavailableView {
                Label("Nada com esta tag", systemImage: "tag")
            } description: {
                Text("Nenhuma gravação marcada com “\(tag)”.")
            } actions: {
                Button("Remover filtro") { navigation.libraryTag = nil }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    @ViewBuilder
    private var tagFilterBar: some View {
        if let tag = navigation.libraryTag {
            HStack {
                Button {
                    navigation.libraryTag = nil
                } label: {
                    Label(tag, systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Remover o filtro da tag \(tag)"))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { recording in
                NavigationLink(value: recording) {
                    RecordingRow(recording: recording)
                }
                .swipeActions(edge: .trailing) {
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        pendingDeletion = recording
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Recording.self) { recording in
            RecordingDetailView(recording: recording)
        }
    }

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

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(DurationFormat.clock(recording.duration))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let summary = recording.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let status = recording.statusNotice {
                Label(status, systemImage: recording.status == .failed ? "exclamationmark.triangle" : "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !recording.tags.isEmpty {
                TagChips(tags: recording.tags)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TagChips: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(tags)
            row(Array(tags.prefix(3)))
            row(Array(tags.prefix(2)))
        }
    }

    private func row(_ tags: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(try! RecallModelContainer.make(inMemory: true))
}
