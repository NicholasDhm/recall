import Speech
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [Recording]
    @State private var settings = AppSettings.shared
    @State private var speechModel = SpeechModelState.shared

    @State private var availableLocales: [Locale] = []
    @State private var diskUsage: Int64 = 0
    @State private var confirmingDeleteAll = false
    @State private var confirmingDeleteAllAgain = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PageTitle("Ajustes", subtitle: String(localized: "Tudo fica neste iPhone"))
                            .padding(.horizontal, -Metrics.gutter)

                        group("Transcrição") {
                            PlainRow(label: String(localized: "Idioma")) {
                                if availableLocales.isEmpty {
                                    Text(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier))
                                } else {
                                    Menu {
                                        Picker("Idioma", selection: $settings.transcriptionLocaleIdentifier) {
                                            ForEach(availableLocales, id: \.identifier) { locale in
                                                Text(AppSettings.displayName(for: locale.identifier(.bcp47)))
                                                    .tag(locale.identifier(.bcp47))
                                            }
                                        }
                                    } label: {
                                        Text(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier))
                                            .foregroundStyle(Color.ember)
                                    }
                                }
                            }
                            Rule()
                            PlainRow(label: String(localized: "Modelo de voz")) {
                                Text(speechModel.label)
                            }

                            if speechModel.isInstalling {
                                HStack(spacing: 12) {
                                    ProgressView(value: speechModel.progress).tint(Color.ember)
                                    Text("\(Int(speechModel.progress * 100))%")
                                        .font(.uiMeta)
                                        .foregroundStyle(Color.inkSoft)
                                }
                                .padding(.bottom, 14)
                            } else if speechModel.needsDownload {
                                Button("Baixar modelo") {
                                    Task { await speechModel.install(for: settings.transcriptionLocale) }
                                }
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.ember)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 14)
                            }

                            if let error = speechModel.error {
                                Text(error)
                                    .font(.uiMeta)
                                    .foregroundStyle(Color.inkSoft)
                                    .padding(.bottom, 14)
                            }

                            note("O áudio é transcrito no próprio iPhone. Nada sai do aparelho.")
                        }

                        group("Apple Intelligence") {
                            PlainRow(label: String(localized: "Status")) {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(TranscriptAnalyzer.availability == .available
                                              ? Color.ember : Color.inkFaint)
                                        .frame(width: 6, height: 6)
                                    Text(TranscriptAnalyzer.availability == .available
                                         ? "Disponível" : "Indisponível")
                                }
                            }
                            if let reason = TranscriptAnalyzer.availability.reason {
                                note(reason)
                            } else {
                                note("Gera resumo, tags e itens de ação.")
                            }
                        }

                        group("Armazenamento") {
                            PlainRow(label: String(localized: "Gravações")) {
                                Text(recordings.count.formatted()).monospacedDigit()
                            }
                            Rule()
                            PlainRow(label: String(localized: "Espaço em disco")) {
                                Text(DurationFormat.byteCount(diskUsage)).monospacedDigit()
                            }
                            Rule()
                            Button(role: .destructive) {
                                confirmingDeleteAll = true
                            } label: {
                                Text("Apagar todas as gravações")
                                    .font(.system(.body))
                                    .foregroundStyle(recordings.isEmpty ? Color.inkFaint : Color.ember)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .disabled(recordings.isEmpty)
                        }

                        Text("Recall \(versionString)")
                            .font(.uiMeta)
                            .foregroundStyle(Color.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                }
                .paperBackground()
            }
            .navigationBarHidden(true)
            .task { await refresh() }
            .onChange(of: settings.transcriptionLocaleIdentifier) {
                Task { await speechModel.refresh(for: settings.transcriptionLocale) }
            }
            .confirmationDialog(
                "Apagar todas as gravações?",
                isPresented: $confirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Apagar tudo", role: .destructive) { confirmingDeleteAllAgain = true }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Isso remove o áudio, as transcrições e as análises deste iPhone.")
            }
            .alert("Tem certeza?", isPresented: $confirmingDeleteAllAgain) {
                Button("Apagar definitivamente", role: .destructive) { deleteEverything() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Não há backup. Esta ação não pode ser desfeita.")
            }
        }
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(text: title).padding(.bottom, 4)
            Rule()
            content()
        }
        .padding(.bottom, 34)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.uiMeta)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refresh() async {
        diskUsage = AudioStore.shared.totalByteCount()

        let supported = await SpeechAssets.supportedLocales()
        availableLocales = AppSettings.offeredLocaleIdentifiers.compactMap { identifier in
            let wanted = Locale(identifier: identifier)
            return supported.first {
                $0.language.languageCode == wanted.language.languageCode && $0.region == wanted.region
            }
        }
        await speechModel.refresh(for: settings.transcriptionLocale)
    }

    private func deleteEverything() {
        RecordingActions.deleteAll(in: modelContext)
        diskUsage = AudioStore.shared.totalByteCount()
    }
}
