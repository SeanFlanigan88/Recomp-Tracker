import SwiftUI
import RecompCore

/// Where a phase tap goes.
struct SessionRoute: Hashable {
    let phase: Phase
    let ordinal: Int
}

/// Home. Three phase blocks, each showing how many of its sessions are done.
/// Tapping one opens the lowest session not yet marked complete.
struct ContentView: View {

    @Environment(\.appDatabase) private var database

    @State private var counts: [Phase: Int] = [:]
    @State private var path: [SessionRoute] = []
    @State private var failure: String?

    private let program = Program.cycle3

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    if let failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(Phase.allCases) { phase in
                        Button {
                            open(phase)
                        } label: {
                            PhaseBlock(
                                phase: phase,
                                completed: counts[phase]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Recomp Tracker")
            .navigationDestination(for: SessionRoute.self) { route in
                SessionView(phase: route.phase, ordinal: route.ordinal)
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .onChange(of: path) { _, newPath in
            // Returning from a session: counts may have moved.
            if newPath.isEmpty {
                Task { await load() }
            }
        }
    }

    private func load() async {
        guard let database else { return }
        do {
            try await database.seedExercises(from: program)
            var fresh: [Phase: Int] = [:]
            for phase in Phase.allCases {
                fresh[phase] = try await database.completedCount(phase: phase)
            }
            counts = fresh
            failure = nil
        } catch {
            failure = "Couldn't load progress: \(error.localizedDescription)"
        }
    }

    private func open(_ phase: Phase) {
        guard let database else { return }
        Task {
            do {
                let ordinal = try await database.pendingOrdinal(phase: phase)
                path.append(SessionRoute(phase: phase, ordinal: ordinal))
            } catch {
                failure = "Couldn't open \(phase.title): \(error.localizedDescription)"
            }
        }
    }
}

private struct PhaseBlock: View {
    let phase: Phase

    /// Nil while loading, so the block never flashes a wrong number.
    let completed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phase.title)
                .font(.title)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var subtitle: String {
        guard let completed else { return " " }
        return "\(completed)/\(Phase.nominalSessionCount) sessions complete"
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, try? AppDatabase.inMemory())
}
