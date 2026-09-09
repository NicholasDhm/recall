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
            List {
                transcriptionSection
                intelligenceSection
                storageSection
                aboutSection
            }
            .navigationTitle("Ajustes")
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

    // MARK: - Sections

    @ViewBuilder
    private var transcriptionSection: some View {
        Section {
            if availableLocales.isEmpty {
                LabeledContent("Idioma", value: AppSettings.displayName(for: settings.transcriptionLocaleIdentifier))
                Text("Este aparelho não reporta nenhum idioma de transcrição. No simulador isso é esperado; em um iPhone com iOS 26 os idiomas aparecem aqui.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Idioma", selection: $settings.transcriptionLocaleIdentifier) {
                    ForEach(availableLocales, id: \.identifier) { locale in
                        Text(AppSettings.displayName(for: locale.identifier(.bcp47)))
                            .tag(locale.identifier(.bcp47))
                    }
                }
            }

            LabeledContent("Modelo de fala", value: speechModel.label)

            if speechModel.isInstalling {
                ProgressView(value: speechModel.progress) {
                    Text("Baixando o modelo")
                }
                .font(.footnote)
            } else if speechModel.needsDownload {
                Button("Baixar modelo", systemImage: "arrow.down.circle") {
                    Task { await speechModel.install(for: settings.transcriptionLocale) }
                }
            }

            if let error = speechModel.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Transcrição")
        } footer: {
            Text("A transcrição acontece no próprio iPhone. Nenhum áudio sai do aparelho.")
        }
    }

    private var intelligenceSection: some View {
        Section {
            LabeledContent("Status", value: intelligenceStatusLabel)
            if let reason = TranscriptAnalyzer.availability.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Usado para gerar resumo, tags e itens de ação. Sem ele o app continua gravando e transcrevendo.")
        }
    }

    private var storageSection: some View {
        Section("Armazenamento") {
            LabeledContent("Gravações", value: recordings.count.formatted())
            LabeledContent("Espaço em disco", value: DurationFormat.byteCount(diskUsage))
            Button("Apagar todas as gravações", systemImage: "trash", role: .destructive) {
                confirmingDeleteAll = true
            }
            .disabled(recordings.isEmpty)
            .tint(.red)
        }
    }

    private var aboutSection: some View {
        Section("Sobre") {
            LabeledContent("Versão", value: versionString)
        }
    }

    // MARK: - Labels

    private var intelligenceStatusLabel: String {
        TranscriptAnalyzer.availability == .available
            ? String(localized: "Disponível")
            : String(localized: "Indisponível")
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

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
