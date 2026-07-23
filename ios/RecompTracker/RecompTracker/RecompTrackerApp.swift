import SwiftUI
import RecompCore

@main
struct RecompTrackerApp: App {
    let appDatabase: AppDatabase

    init() {
        do {
            appDatabase = try AppDatabase.standard()
        } catch {
            // Migration failure on launch is worth crashing over rather than
            // silently degrading into a broken app. Revisit if we ever ship
            // this to anyone but me.
            fatalError("Failed to open database on launch: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, appDatabase)
        }
    }
}

// MARK: - Environment injection
//
// The environment value is Optional so SwiftUI can propagate a nil default
// through the view hierarchy without triggering a fatalError. Consumers that
// need the database check for nil at the point of use; a missing injection
// crashes there with a useful stack, rather than during SwiftUI's internal
// keypath materialization (which read-before-writes).

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase? = nil
}

extension EnvironmentValues {
    var appDatabase: AppDatabase? {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}
