import SwiftUI
import RecompCore

/// Placeholder shell. The real Home screen (three phase blocks) lands with the
/// UI commit; this exists so the app target builds and launches after the strip.
struct ContentView: View {

    var body: some View {
        NavigationStack {
            Text("Recomp Tracker")
                .foregroundStyle(.secondary)
                .navigationTitle("Home")
        }
        // Force dark by default per Sean's preference. Not tied to the system
        // appearance — if the phone is on light mode, this app is still dark.
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, try? AppDatabase.inMemory())
}
