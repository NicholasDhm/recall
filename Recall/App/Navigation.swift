import Foundation
import Observation

enum RootTab: Hashable, Sendable {
    case record
    case library
    case insights
    case settings
}

@MainActor
@Observable
final class Navigation {
    var selectedTab: RootTab = .record
    /// Set from Insights when a tag is tapped; the Library filters on it and clears it.
    var libraryTag: String?

    init(selectedTab: RootTab = .record) {
        self.selectedTab = selectedTab
    }

    func showLibrary(taggedWith tag: String) {
        libraryTag = tag
        selectedTab = .library
    }
}
