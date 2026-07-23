import SwiftUI
import RecompCore

struct ContentView: View {
    var body: some View {
        TabView {
            LogTab()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }

            WorkoutsTab()
                .tabItem { Label("Workouts", systemImage: "dumbbell") }

            MetricsTab()
                .tabItem { Label("Metrics", systemImage: "chart.line.uptrend.xyaxis") }

            PhotosTab()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }

            CheckInsTab()
                .tabItem { Label("Check-ins", systemImage: "checkmark.circle") }
        }
    }
}

// MARK: - Placeholder tabs
//
// Each tab is a NavigationStack + a Text view for now. The NavigationStack
// wrappers are here so titles render correctly and so we're not restructuring
// the view hierarchy when we add real content in commit #4.

private struct LogTab: View {
    var body: some View {
        NavigationStack {
            Text("Daily log lives here.")
                .navigationTitle("Log")
        }
    }
}

private struct WorkoutsTab: View {
    var body: some View {
        NavigationStack {
            Text("Workouts and sets live here.")
                .navigationTitle("Workouts")
        }
    }
}

private struct MetricsTab: View {
    var body: some View {
        NavigationStack {
            Text("Body composition, sleep, HRV live here.")
                .navigationTitle("Metrics")
        }
    }
}

private struct PhotosTab: View {
    var body: some View {
        NavigationStack {
            Text("Progress photos live here.")
                .navigationTitle("Photos")
        }
    }
}

private struct CheckInsTab: View {
    var body: some View {
        NavigationStack {
            Text("Weekly, biweekly, monthly check-ins live here.")
                .navigationTitle("Check-ins")
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, try! AppDatabase.inMemory())
}
