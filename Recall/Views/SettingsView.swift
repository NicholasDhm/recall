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
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader("Ajustes", subtitle: "Tudo fica neste iPhone")
                    .padding(.horizontal, -Metrics.gutter)

                transcription
                intelligence
                storage

                Text("Recall \(versionString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screenBackground()
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

    // MARK: - Groups

    private var transcription: some View {
        CardGroup(
            title: "Transcrição",
            footnote: "O áudio é transcrito no próprio iPhone. Nada sai do aparelho."
        ) {
            CardRow(label: "Idioma") {
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
                        HStack(spacing: 4) {
                            Text(AppSettings.displayName(for: settings.transcriptionLocaleIdentifier))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                    }
                }
            }

            CardRow(label: "Modelo de voz", showsDivider: speechModel.needsDownload || speechModel.isInstalling) {
                HStack(spacing: 8) {
                    if speechModel.isReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Text(speechModel.label)
                }
            }

            if speechModel.isInstalling {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: speechModel.progress)
                    Text("Baixando \(Int(speechModel.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            } else if speechModel.needsDownload {
                Button {
                    Task { await speechModel.install(for: settings.transcriptionLocale) }
                } label: {
                    Label("Baixar modelo", systemImage: "arrow.down.circle")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if let error = speechModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var intelligence: some View {
        CardGroup(
            title: "Apple Intelligence",
            footnote: "Gera resumo, tags e itens de ação. Sem ele o app continua gravando e transcrevendo."
        ) {
            CardRow(label: "Status", showsDivider: false) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(TranscriptAnalyzer.availability == .available ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(TranscriptAnalyzer.availability == .available ? "Disponível" : "Indisponível")
                }
            }
            if let reason = TranscriptAnalyzer.availability.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Armazenamento")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            HStack(spacing: 12) {
                statTile(value: recordings.count.formatted(), label: "Gravações")
                statTile(value: DurationFormat.byteCount(diskUsage), label: "Em disco")
            }

            Button(role: .destructive) {
                confirmingDeleteAll = true
            } label: {
                Label("Apagar todas as gravações", systemImage: "trash")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(recordings.isEmpty ? Color.secondary : Color.red)
            .background(
                RoundedRectangle(cornerRadius: Metrics.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .disabled(recordings.isEmpty)
            .padding(.top, 4)
        }
    }

    private func statTile(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 14)
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
