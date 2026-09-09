import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let locale = "transcriptionLocaleIdentifier"
    }

    var transcriptionLocaleIdentifier: String {
        didSet { UserDefaults.standard.set(transcriptionLocaleIdentifier, forKey: Key.locale) }
    }

    init(defaults: UserDefaults = .standard) {
        transcriptionLocaleIdentifier = defaults.string(forKey: Key.locale) ?? "pt-BR"
    }

    var transcriptionLocale: Locale {
        Locale(identifier: transcriptionLocaleIdentifier)
    }

    /// The locales the app offers. Only those the transcriber actually supports on this
    /// device are shown in Settings.
    static let offeredLocaleIdentifiers = ["pt-BR", "en-US"]

    static func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)?.capitalized
            ?? identifier
    }
}
