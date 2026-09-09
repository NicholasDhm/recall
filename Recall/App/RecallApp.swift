import SwiftData
import SwiftUI

@main
struct RecallApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try RecallModelContainer.make()
        } catch {
            fatalError("could not open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
