import Foundation
import Observation
import Speech

/// Shared, observable state of the on-device speech model, so the Gravar screen and
/// Ajustes always agree and the model can be fetched from wherever the user notices
/// it is missing.
@MainActor
@Observable
final class SpeechModelState {
    static let shared = SpeechModelState()

    private(set) var status: AssetInventory.Status?
    private(set) var isInstalling = false
    private(set) var progress: Double = 0
    private(set) var error: String?

    var isReady: Bool { status == .installed }
    var isUnsupported: Bool { status == .unsupported }
    /// Present but not downloaded yet — the case that used to silently disable the
    /// live transcript with nothing on screen to explain it.
    var needsDownload: Bool { status == .supported || status == .downloading }

    func refresh(for locale: Locale) async {
        status = await SpeechAssets.status(for: locale)
    }

    func install(for locale: Locale) async {
        guard !isInstalling else { return }
        isInstalling = true
        progress = 0
        error = nil
        defer { isInstalling = false }

        do {
            try await SpeechAssets.install(locale) { fraction in
                Task { @MainActor [weak self] in self?.progress = fraction }
            }
            await SpeechAssets.reserve(locale)
        } catch {
            self.error = error.localizedDescription
        }
        await refresh(for: locale)
    }

    var label: String {
        switch status {
        case .installed: String(localized: "Baixado")
        case .downloading: String(localized: "Baixando")
        case .supported: String(localized: "Não baixado")
        case .unsupported: String(localized: "Não disponível")
        case nil: String(localized: "Verificando…")
        @unknown default: String(localized: "Não disponível")
        }
    }
}
