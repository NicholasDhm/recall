import SwiftData
import SwiftUI

@main
struct RecallApp: App {
    private let container: ModelContainer
    @State private var pipeline: RecordingPipeline

    init() {
        let container: ModelContainer
        do {
            container = try RecallModelContainer.make()
        } catch {
            fatalError("could not open the local store: \(error)")
        }
        self.container = container
        _pipeline = State(initialValue: RecordingPipeline(context: container.mainContext))

        #if DEBUG
        if LaunchOptions.seedsFixtures {
            MainActor.assumeIsolated { LaunchOptions.seedFixtures(into: container.mainContext) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pipeline)
                .task { pipeline.resume() }
        }
        .modelContainer(container)
    }
}
