import SwiftUI
import SwiftData

@main
struct LeDetourageApp: App {
    /// Shared SwiftData stack for the sticker drawer.
    let modelContainer: ModelContainer = {
        let schema = Schema([SavedSticker.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // If the on-disk store can't open (e.g. a schema migration during
            // development), fall back to an in-memory store so the app still runs.
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1120, height: 820)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
