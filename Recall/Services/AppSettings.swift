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
}
