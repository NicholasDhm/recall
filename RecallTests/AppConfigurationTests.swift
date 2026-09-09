import Foundation
import Testing

@testable import Recall

@Suite("App configuration")
struct AppConfigurationTests {
    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    @Test("Bundle identifier is the one provisioned for the personal team")
    func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.nickdhm.recall")
    }

    @Test("Privacy usage descriptions are present and non-empty")
    func usageDescriptions() {
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            let value = info[key] as? String
            #expect(value?.isEmpty == false, "missing \(key)")
        }
    }

    @Test("Audio background mode is declared so recording survives a locked screen")
    func backgroundModes() {
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        #expect(modes.contains("audio"))
    }

    @Test("The app is portrait only")
    func orientations() {
        let orientations = info["UISupportedInterfaceOrientations"] as? [String] ?? []
        #expect(orientations == ["UIInterfaceOrientationPortrait"])
    }

    @Test("Encryption exemption is declared so device installs do not prompt")
    func encryptionDeclaration() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }
}
