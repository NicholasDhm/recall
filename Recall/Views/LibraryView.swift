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
            ZStack {
                Color.paper.ignoresSafeArea()

                if recordings.isEmpty {
                    VStack(spacing: 0) {
                        PageTitle("Biblioteca")
                        emptyLibrary
                        Spacer()
                    }
                } else {
                    timeline
                }
            }
            .navigationBarHidden(true)
            .task {
                #if DEBUG
                if LaunchOptions.opensFirstRecording, path.isEmpty, let first = recordings.first {
                    path.append(first)
                }
                #endif
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

    private var timeline: some View {
        List {
            Group {
                PageTitle(title: "Biblioteca", subtitle: subtitle) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel(Text("Importar áudio"))
                }
                .padding(.horizontal, -Metrics.gutter)

                SearchField(text: $query)
                    .padding(.bottom, 8)

                if let tag = navigation.libraryTag {
                    Button {
                        navigation.libraryTag = nil
                    } label: {
                        HStack(spacing: 5) {
                            Text(tag).font(.system(.subheadline, weight: .medium))
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .foregroundStyle(Color.ember)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                    .accessibilityLabel(Text("Remover o filtro da tag \(tag)"))
                }

                if filtered.isEmpty { emptyResult }
            }
            .plainRow()

            ForEach(groups, id: \.group) { section in
                Section {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, recording in
                        VStack(spacing: 0) {
                            if index > 0 { Rule() }
                            Button {
                                path.append(recording)
                            } label: {
                                RecordingEntry(recording: recording)
                            }
                            .buttonStyle(.plain)
                        }
                        .plainRow()
                        .swipeActions(edge: .trailing) {
                            Button("Excluir", systemImage: "trash", role: .destructive) {
                                pendingDeletion = recording
                            }
                        }
                    }
                } header: {
                    Marker(text: section.group.title)
                        .textCase(nil)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                        .plainRow()
                }
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .paperBackground()
    }

    private var subtitle: String {
        let total = recordings.reduce(0) { $0 + $1.duration }
        return String(localized: "\(recordings.count) gravações · \(DurationFormat.clock(total))")
    }

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Text("Nada gravado ainda.")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text("Grave na aba Gravar, ou traga um áudio que já existe.")
                .font(.uiMeta)
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
            Button("Importar áudio") { isImporting = true }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.ember)
                .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }

    private var emptyResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigation.libraryTag == nil ? "Nada encontrado." : "Nada com esta tag.")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
        }
        .padding(.top, 30)
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

private extension View {
    /// Strips every piece of `List` chrome so rows sit directly on the paper.
    func plainRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Metrics.gutter, bottom: 0, trailing: Metrics.gutter))
    }
}

struct RecordingEntry: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(recording.title)
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                if recording.source == .imported {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .semibold))
                }
                Text(recording.createdAt, format: .dateTime.hour().minute())
                Text(verbatim: "·")
                Text(DurationFormat.clock(recording.duration)).monospacedDigit()
                if let notice = recording.statusNotice {
                    Text(verbatim: "·")
                    Text(notice)
                }
            }
            .font(.uiMeta)
            .foregroundStyle(recording.status == .failed ? Color.ember : Color.inkSoft)

            if let summary = recording.summary, !summary.isEmpty {
                Text(summary)
                    .font(.readingSmall)
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(2)
                    .lineSpacing(3)
                    .padding(.top, 1)
            }

            if !recording.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recording.tags.prefix(3), id: \.self) { Chip(text: $0) }
                }
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

/// Quiet search line. `.searchable` renders the system search bar, the most
/// recognisably stock chrome on the screen.
private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.inkFaint)

                TextField("Buscar", text: $text)
                    .font(.system(.subheadline))
                    .foregroundStyle(Color.ink)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .submitLabel(.search)

                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Limpar busca"))
                }
            }
            Rule()
        }
    }
}
