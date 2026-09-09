import Foundation
import Speech

/// Availability and download of the on-device speech models. Nothing here touches the
/// network directly — `AssetInventory` fetches Apple's models through the system.
enum SpeechAssets {
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    /// Maps a user-facing identifier such as `pt-BR` onto the locale the transcriber
    /// actually ships, or nil when the language is unsupported.
    static func resolve(_ locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    static func status(for locale: Locale) async -> AssetInventory.Status {
        await AssetInventory.status(forModules: [transcriber(for: locale)])
    }

    static func isInstalled(_ locale: Locale) async -> Bool {
        await status(for: locale) == .installed
    }

    /// Downloads and installs the model for `locale` if it is not already there,
    /// reporting 0...1 progress. No-op when the asset is present.
    static func install(
        _ locale: Locale,
        progress handler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber(for: locale)]
        ) else {
            return
        }

        let progress = request.progress
        let poll = handler.map { handler in
            Task {
                while !Task.isCancelled {
                    handler(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
        defer { poll?.cancel() }

        try await request.downloadAndInstall()
        handler?(1)
    }

    /// Reserving keeps the model from being reclaimed. The system caps how many
    /// locales an app may hold, so a failure here is not fatal.
    static func reserve(_ locale: Locale) async {
        _ = try? await AssetInventory.reserve(locale: locale)
    }

    private static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .transcription)
    }
}
