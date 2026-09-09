import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var query = ""
    @State private var pendingDeletion: Recording?

    private var filtered: [Recording] {
        query.isEmpty ? recordings : recordings.filter { $0.matches(query: query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhuma gravação", systemImage: "waveform")
                    } description: {
                        Text("Grave na aba Gravar ou importe um arquivo de áudio.")
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $query, prompt: Text("Buscar por título, transcrição ou tag"))
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
