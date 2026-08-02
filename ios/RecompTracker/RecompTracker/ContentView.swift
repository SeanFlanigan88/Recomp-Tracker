import SwiftUI
import RecompCore

struct ContentView: View {

    /// Tab selection is state so the Log tab's "Session" row can programmatically
    /// jump to Workouts. Keep this minimal — no routing framework, just a tab
    /// enum and a couple of tags.
    @State private var selectedTab: Tab = .log

    enum Tab: Hashable {
        case log, workouts, metrics, photos, checkIns
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LogTab(onOpenWorkouts: { selectedTab = .workouts })
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .tag(Tab.log)

            WorkoutsTab()
                .tabItem { Label("Workouts", systemImage: "dumbbell") }
                .tag(Tab.workouts)

            MetricsTab()
                .tabItem { Label("Metrics", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.metrics)

            PhotosTab()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                .tag(Tab.photos)

            CheckInsTab()
                .tabItem { Label("Check-ins", systemImage: "checkmark.circle") }
                .tag(Tab.checkIns)
        }
        // Force dark by default per Sean's preference. Not tied to the
        // system appearance — if the phone is on light mode, this app is
        // still dark. Revisit if we ever add a user-facing appearance
        // toggle in settings.
        .preferredColorScheme(.dark)
    }
}

// MARK: - Placeholder tabs
//
// LogTab, WorkoutsTab, and PhotosTab are now real views in their own files.
// The rest stay as placeholders until their respective commits. Each is
// wrapped in NavigationStack so title rendering matches what the real views
// will look like.

private struct MetricsTab: View {
    var body: some View {
        NavigationStack {
            Text("Body composition, sleep, HRV live here.")
                .navigationTitle("Metrics")
        }
        .keyboardDoneToolbar()
    }
}

private struct CheckInsTab: View {
    var body: some View {
        NavigationStack {
            Text("Weekly, biweekly, monthly check-ins live here.")
                .navigationTitle("Check-ins")
        }
        .keyboardDoneToolbar()
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, try? AppDatabase.inMemory())
}
