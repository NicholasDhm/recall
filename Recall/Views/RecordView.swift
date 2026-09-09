import AVFoundation
import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var recorder = AudioRecorder()
    @State private var settings = AppSettings.shared
    @State private var permission = AudioRecorder.permission
    @State private var errorMessage: String?
    @State private var openedRecording: Recording?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(DurationFormat.clock(recorder.elapsed))
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("Tempo de gravação"))
                    .accessibilityValue(Text(DurationFormat.clock(recorder.elapsed)))

                LevelMeter(levels: recorder.levels, isActive: recorder.isRecording)
                    .frame(height: 88)
                    .padding(.horizontal)

                Spacer()

                if permission == .denied {
                    deniedNotice
                } else {
                    recordButton
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Gravar")
            .navigationDestination(item: $openedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .alert("Não foi possível gravar", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var recordButton: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                    .frame(width: 108, height: 108)
                RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 44, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(
                        width: recorder.isRecording ? 44 : 88,
                        height: recorder.isRecording ? 44 : 88
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? Text("Parar gravação") : Text("Iniciar gravação"))
    }

    private var deniedNotice: some View {
        ContentUnavailableView {
            Label("Microfone bloqueado", systemImage: "mic.slash")
        } description: {
            Text("O Recall precisa do microfone para gravar. Libere o acesso nos Ajustes do iPhone.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes", destination: url)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggle() {
        if recorder.isRecording {
            finish()
        } else {
            Task { await begin() }
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
        }
    }

    private func finish() {
        guard let finished = recorder.stop() else { return }
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
        modelContext.insert(recording)
        try? modelContext.save()
        pendingID = UUID()
        openedRecording = recording
    }

    @State private var pendingID = UUID()
}

#Preview {
    RecordView()
        .modelContainer(try! RecallModelContainer.make(inMemory: true))
}
