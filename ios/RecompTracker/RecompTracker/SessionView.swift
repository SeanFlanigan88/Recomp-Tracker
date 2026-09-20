import SwiftUI
import RecompCore

/// One session of a phase: the prescription, the inputs, and last time's
/// numbers as placeholders.
///
/// Entries save on focus loss and again before completion or navigation, so
/// there is no Save button to forget mid-set.
struct SessionView: View {

    let phase: Phase

    @Environment(\.appDatabase) private var database

    @State private var ordinal: Int
    @State private var snapshot: SessionSnapshot?
    @State private var drafts: [Int64: Draft] = [:]
    @State private var failure: String?
    @FocusState private var focused: FieldID?

    private let program = Program.cycle3

    init(phase: Phase, ordinal: Int) {
        self.phase = phase
        _ordinal = State(initialValue: ordinal)
    }

    // MARK: - Local edit state

    private struct Draft: Equatable {
        var weight: String
        var reps: String

        init(_ log: ExerciseLog?) {
            weight = log?.weightLb.map(Self.format) ?? ""
            reps = log?.reps.map(String.init) ?? ""
        }

        static func format(_ value: Double) -> String {
            value == value.rounded()
                ? String(Int(value))
                : String(format: "%.1f", value)
        }
    }

    private struct FieldID: Hashable {
        enum Kind { case weight, reps }
        let exerciseId: Int64
        let kind: Kind
    }

    // MARK: - Body

    var body: some View {
        List {
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let snapshot {
                headerSection(snapshot)

                if snapshot.session.isLifting {
                    exerciseSection(snapshot)
                    mobilitySection
                } else if let detail = snapshot.session.detail {
                    Section {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                completionSection(snapshot)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Session \(ordinal) of \(Phase.nominalSessionCount)")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .task(id: ordinal) { await load() }
        .onChange(of: focused) { previous, _ in
            if let previous {
                Task { await commit(exerciseId: previous.exerciseId) }
            }
        }
    }

    // MARK: - Sections

    private func headerSection(_ snapshot: SessionSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.session.name)
                    .font(.headline)

                if let cardio = snapshot.session.cardio {
                    Text(cardio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func exerciseSection(_ snapshot: SessionSnapshot) -> some View {
        Section {
            ForEach(snapshot.rows, id: \.exerciseId) { row in
                exerciseRow(row)
            }
        }
    }

    private func exerciseRow(_ row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise.name)
                        .font(.body)
                    if let cue = row.exercise.cue {
                        Text(cue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Text(row.exercise.prescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: binding(for: row.exerciseId, \.weight),
                    prompt: Text(ghostWeight(row)).foregroundStyle(.tertiary)
                )
                .keyboardType(.decimalPad)
                .focused($focused, equals: FieldID(exerciseId: row.exerciseId, kind: .weight))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)

                Text("lb")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "",
                    text: binding(for: row.exerciseId, \.reps),
                    prompt: Text(ghostReps(row)).foregroundStyle(.tertiary)
                )
                .keyboardType(.numberPad)
                .focused($focused, equals: FieldID(exerciseId: row.exerciseId, kind: .reps))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)

                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var mobilitySection: some View {
        Section("Mobility finisher · \(program.mobilityFinisherDuration)") {
            Text(program.mobilityFinisher.map { "\($0.name) \($0.reps)" }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func completionSection(_ snapshot: SessionSnapshot) -> some View {
        Section {
            Button {
                Task { await toggleComplete(snapshot) }
            } label: {
                Label(
                    snapshot.isComplete ? "Completed" : "Mark Complete",
                    systemImage: snapshot.isComplete ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(snapshot.isComplete ? .green : .accentColor)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            HStack {
                Button {
                    Task { await move(to: ordinal - 1) }
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(ordinal <= 1)

                Spacer()

                Button {
                    Task { await move(to: ordinal + 1) }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
            }
            .buttonStyle(.bordered)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Ghosts

    private func ghostWeight(_ row: SessionRow) -> String {
        guard let value = row.lastTime?.weightLb else { return "—" }
        return Draft.format(value)
    }

    private func ghostReps(_ row: SessionRow) -> String {
        guard let value = row.lastTime?.reps else { return "—" }
        return String(value)
    }

    // MARK: - Editing

    private func binding(
        for exerciseId: Int64,
        _ keyPath: WritableKeyPath<Draft, String>
    ) -> Binding<String> {
        Binding(
            get: { drafts[exerciseId]?[keyPath: keyPath] ?? "" },
            set: { newValue in
                var draft = drafts[exerciseId] ?? Draft(nil)
                draft[keyPath: keyPath] = newValue
                drafts[exerciseId] = draft
            }
        )
    }

    // MARK: - Data

    private func load() async {
        guard let database else { return }
        do {
            let fresh = try await database.sessionSnapshot(
                program: program, phase: phase, ordinal: ordinal
            )
            snapshot = fresh
            drafts = Dictionary(
                uniqueKeysWithValues: fresh.rows.map { ($0.exerciseId, Draft($0.logged)) }
            )
            failure = nil
        } catch {
            failure = "Couldn't load session: \(error.localizedDescription)"
        }
    }

    /// Write one exercise's draft. Both fields go together, since a log row
    /// holds one weight and one rep count.
    private func commit(exerciseId: Int64) async {
        guard let database,
              let snapshot,
              let row = snapshot.rows.first(where: { $0.exerciseId == exerciseId }),
              let draft = drafts[exerciseId]
        else { return }

        let weight = Double(draft.weight.trimmingCharacters(in: .whitespaces))
        let reps = Int(draft.reps.trimmingCharacters(in: .whitespaces))

        guard weight != row.logged?.weightLb || reps != row.logged?.reps else { return }

        do {
            try await database.logEntry(
                phase: phase,
                ordinal: ordinal,
                exerciseName: row.exercise.name,
                weightLb: weight,
                reps: reps
            )
            await load()
        } catch {
            failure = "Couldn't save \(row.exercise.name): \(error.localizedDescription)"
        }
    }

    /// Flush every field before an action that leaves the current state.
    private func commitAll() async {
        focused = nil
        guard let snapshot else { return }
        for row in snapshot.rows {
            await commit(exerciseId: row.exerciseId)
        }
    }

    private func toggleComplete(_ snapshot: SessionSnapshot) async {
        guard let database else { return }
        await commitAll()
        do {
            _ = try await database.setCompleted(
                phase: phase, ordinal: ordinal, !snapshot.isComplete
            )
            await load()
        } catch {
            failure = "Couldn't update completion: \(error.localizedDescription)"
        }
    }

    private func move(to target: Int) async {
        guard target >= 1 else { return }
        await commitAll()
        ordinal = target
    }
}

#Preview {
    NavigationStack {
        SessionView(phase: .one, ordinal: 1)
            .environment(\.appDatabase, try? AppDatabase.inMemory())
    }
}
