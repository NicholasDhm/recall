import Foundation
import SwiftData

enum RecallModelContainer {
    static let schema = Schema([Recording.self, TranscriptSegment.self])

    /// CloudKit stays off: a free Personal Team cannot provision the entitlement.
    /// Turning it on later is a one-line change to `cloudKitDatabase`.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // iOS does not create Application Support; the default store lives there.
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
