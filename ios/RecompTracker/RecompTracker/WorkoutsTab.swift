import SwiftUI
import RecompCore

/// The Workouts tab. Reads today's day-of-week from the cycle 2 program and
/// renders the appropriate shape:
///   - Rest day (Sunday) → note only, no inputs, no workout row created
///   - Cardio day (Tuesday) → cardio note + duration/HR inputs
///   - Lifting day (Mon/Wed/Thu/Fri) → sections per exercise with sets grid
///   - Hybrid day (Saturday) → cardio inputs + accessory lift sections
///
/// Saves per set on focus loss. No Save button. Same reasoning as the Log
/// tab: at the gym you're distracted and every tap-away needs to persist.
struct WorkoutsTab: View {

    // MARK: - Injected

    @Environment(\.appDatabase) private var appDatabase: AppDatabase?

    // MARK: - Editable state

    @State private var date = Date()
    @State private var showDatePicker = false
    @State private var workoutId: Int64?
    @State private var setState: [String: [SetInputRow]] = [:]
    @State private var cardioDurationMin: Int?
    @State private var cardioAvgHr: Int?
    @State private var notes: String = ""
    @State private var didInitialLoad = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case set(exerciseId: String, index: Int, kind: SetFieldKind)
        case cardioDuration
        case cardioHr
        case notes
    }
    private enum SetFieldKind: Hashable { case weight, reps }

    private struct SetInputRow: Equatable {
        var weightLb: Double? = nil
        var reps: Int? = nil
        var isTopSet: Bool = false
        var dbId: Int64? = nil
    }

    // MARK: - Computed

    private var programDay: ProgramDay {
        Program.cycle2.day(for: date)
    }

    private var weekday: Weekday {
        Weekday.from(date: date)
    }

    private var navTitle: String {
        "\(weekday.longName) · \(programDay.name)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(programDay.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !isToday {
                    offTodayBanner
                }
                content
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !isToday {
                        Button("Today") { date = Date() }
                    }
                    Button {
                        showDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Pick a date")
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .keyboardDoneToolbar()
            .task {
                guard !didInitialLoad else { return }
                initializeSetStateForProgram()
                await loadFromDatabase()
                didInitialLoad = true
            }
            .onChange(of: date) { _, _ in
                Task { await reloadForCurrentDate() }
            }
            .onChange(of: focusedField) { oldValue, _ in
                Task { await saveOnFocusLoss(from: oldValue) }
            }
        }
    }

    // MARK: - Date-picker views

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Amber banner shown when the tab is viewing a past date. Compact so it
    /// doesn't dominate the layout, but present enough that you can't
    /// forget which day you're logging into.
    private var offTodayBanner: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    Text(relativeDayString(for: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } footer: {
            Text("Backfilling a past date. New sets recompute PR flags across all logged sessions.")
        }
    }

    /// Modal sheet housing a graphical date picker constrained to the
    /// current cycle. Done applies; Cancel dismisses without changing.
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $date,
                in: cycleDateRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Backfill window: cycle start through today. Anything outside is
    /// disabled by the DatePicker itself, so we can't pick a date the
    /// program doesn't know how to render.
    private var cycleDateRange: ClosedRange<Date> {
        let start = Program.cycle2.startDate ?? Date()
        let today = Calendar.current.startOfDay(for: Date())
        // Guard against a degenerate range if startDate is somehow in the
        // future — collapse to a single-day range on today.
        return min(start, today)...today
    }

    private func relativeDayString(for target: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: target)
        let diff = cal.dateComponents([.day], from: day, to: today).day ?? 0
        if diff == 0 { return "Today" }
        if diff == 1 { return "Yesterday" }
        if diff > 1  { return "\(diff) days ago" }
        return "In \(-diff) days"
    }

    /// Discard editable state and reload for the newly-picked date. Runs
    /// after every date change (including tapping Today from a past date).
    private func reloadForCurrentDate() async {
        setState = [:]
        workoutId = nil
        cardioDurationMin = nil
        cardioAvgHr = nil
        notes = ""
        initializeSetStateForProgram()
        await loadFromDatabase()
    }

    @ViewBuilder
    private var content: some View {
        switch programDay.kind {
        case .rest(let note):
            Section {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .cardio(let note):
            cardioSection(note: note)
            sessionNotesSection

        case .lifting(let exercises):
            ForEach(exercises) { exerciseSection($0) }
            sessionNotesSection

        case .hybrid(let cardioNote, let exercises):
            cardioSection(note: cardioNote)
            ForEach(exercises) { exerciseSection($0) }
            sessionNotesSection
        }
    }

    // MARK: - Sections

    private func cardioSection(note: String) -> some View {
        Section("Cardio") {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Duration")
                Spacer()
                TextField("—", value: $cardioDurationMin, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .cardioDuration)
                    .submitLabel(.done)
                Text("min")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            HStack {
                Text("Avg HR")
                Spacer()
                TextField("—", value: $cardioAvgHr, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .cardioHr)
                    .submitLabel(.done)
                Text("bpm")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private func exerciseSection(_ ex: ProgramExercise) -> some View {
        Section {
            // Header row: exercise name + meta line.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ex.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    if ex.isAnchor {
                        Text("ANCHOR")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(metaLine(for: ex))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            // Column header for the sets grid — makes the numeric fields
            // legible without cluttering each row with unit labels.
            HStack(spacing: 12) {
                Text("#")
                    .frame(width: 20, alignment: .leading)
                Spacer()
                Text("Weight")
                    .frame(width: 90, alignment: .trailing)
                Text("Reps")
                    .frame(width: 55, alignment: .trailing)
                Text("")
                    .frame(width: 30, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            ForEach(0..<ex.sets, id: \.self) { i in
                setRow(for: ex, index: i)
            }
        }
    }

    private func setRow(for ex: ProgramExercise, index: Int) -> some View {
        let isTop = setState[ex.id]?[safe: index]?.isTopSet ?? false
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            Spacer()

            TextField(
                "—",
                value: weightBinding(exerciseId: ex.id, index: index),
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 90)
            .focused($focusedField, equals: .set(exerciseId: ex.id, index: index, kind: .weight))
            .submitLabel(.next)

            TextField(
                "—",
                value: repsBinding(exerciseId: ex.id, index: index),
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 55)
            .focused($focusedField, equals: .set(exerciseId: ex.id, index: index, kind: .reps))
            .submitLabel(.done)

            Text(isTop ? "TOP" : "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var sessionNotesSection: some View {
        Section("Session Notes") {
            TextField("Form cues, PRs, tweaks...", text: $notes, axis: .vertical)
                .lineLimit(3...)
                .focused($focusedField, equals: .notes)
        }
    }

    // MARK: - Bindings

    private func weightBinding(exerciseId: String, index: Int) -> Binding<Double?> {
        Binding(
            get: { setState[exerciseId]?[safe: index]?.weightLb },
            set: { newValue in
                ensureRowExists(exerciseId: exerciseId, index: index)
                setState[exerciseId]?[index].weightLb = newValue
            }
        )
    }

    private func repsBinding(exerciseId: String, index: Int) -> Binding<Int?> {
        Binding(
            get: { setState[exerciseId]?[safe: index]?.reps },
            set: { newValue in
                ensureRowExists(exerciseId: exerciseId, index: index)
                setState[exerciseId]?[index].reps = newValue
            }
        )
    }

    private func ensureRowExists(exerciseId: String, index: Int) {
        if setState[exerciseId] == nil {
            if let ex = programDay.exercises.first(where: { $0.id == exerciseId }) {
                setState[exerciseId] = Array(repeating: SetInputRow(), count: ex.sets)
            }
        }
    }

    // MARK: - Labels

    private func metaLine(for ex: ProgramExercise) -> String {
        var parts = ["\(ex.sets) × \(ex.reps)"]
        if let rest = ex.rest { parts.append(rest) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Load

    private func initializeSetStateForProgram() {
        var initial: [String: [SetInputRow]] = [:]
        for ex in programDay.exercises {
            initial[ex.id] = Array(repeating: SetInputRow(), count: ex.sets)
        }
        setState = initial
    }

    private func loadFromDatabase() async {
        guard let db = appDatabase else { return }
        do {
            let snap = try await db.workoutDaySnapshot(on: date)
            guard let workout = snap.workout else { return }
            self.workoutId = workout.id
            self.cardioDurationMin = workout.durationMin
            self.cardioAvgHr = workout.avgHr
            self.notes = workout.notes ?? ""

            // Map from DB exercise ids back to program exercise ids via name.
            // A DB query per program exercise is fine at this scale (≤8).
            for progEx in programDay.exercises {
                guard let dbEx = try await db.exercise(named: progEx.name),
                      let dbExId = dbEx.id,
                      let sets = snap.setsByExerciseId[dbExId]
                else { continue }

                for s in sets {
                    let idx = s.setNumber - 1
                    guard idx >= 0, idx < (setState[progEx.id]?.count ?? 0) else { continue }
                    setState[progEx.id]?[idx] = SetInputRow(
                        weightLb: s.weightLb,
                        reps: s.reps,
                        isTopSet: s.isTopSet,
                        dbId: s.id
                    )
                }
            }
        } catch {
            print("WorkoutsTab load failed: \(error)")
        }
    }

    // MARK: - Save

    private func saveOnFocusLoss(from previous: Field?) async {
        switch previous {
        case .set(let exerciseId, let index, _):
            await saveSet(exerciseId: exerciseId, index: index)
        case .cardioDuration, .cardioHr:
            await saveCardioFields()
        case .notes:
            await saveNotes()
        case .none:
            break
        }
    }

    private func saveSet(exerciseId: String, index: Int) async {
        guard let db = appDatabase else { return }
        guard let progEx = programDay.exercises.first(where: { $0.id == exerciseId }) else { return }
        guard let sessionType = programDay.sessionType else { return }
        guard let row = setState[exerciseId]?[safe: index] else { return }

        do {
            let wid = try await ensureWorkoutId(db: db, sessionType: sessionType)
            let dbExId = try await db.getOrCreateExercise(name: progEx.name, category: progEx.category)

            try await db.upsertSet(
                workoutId: wid,
                exerciseId: dbExId,
                setNumber: index + 1,
                weightLb: row.weightLb,
                reps: row.reps
            )

            // Refresh top-set flags for this exercise from the DB.
            let refreshed = try await db.sets(workoutId: wid, exerciseId: dbExId)
            for s in refreshed {
                let idx = s.setNumber - 1
                guard idx >= 0, idx < (setState[exerciseId]?.count ?? 0) else { continue }
                setState[exerciseId]?[idx].isTopSet = s.isTopSet
                setState[exerciseId]?[idx].dbId = s.id
            }
        } catch {
            print("saveSet failed: \(error)")
        }
    }

    private func saveCardioFields() async {
        guard let db = appDatabase else { return }
        guard let sessionType = programDay.sessionType else { return }
        do {
            try await db.updateWorkoutFields(
                on: date,
                sessionType: sessionType,
                durationMin: cardioDurationMin,
                avgHr: cardioAvgHr
            )
            if workoutId == nil {
                workoutId = try await db.workout(on: date)?.id
            }
        } catch {
            print("saveCardioFields failed: \(error)")
        }
    }

    private func saveNotes() async {
        guard let db = appDatabase else { return }
        guard let sessionType = programDay.sessionType else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try await db.updateWorkoutFields(on: date, sessionType: sessionType, clearNotes: true)
            } else {
                try await db.updateWorkoutFields(on: date, sessionType: sessionType, notes: trimmed)
            }
            if workoutId == nil {
                workoutId = try await db.workout(on: date)?.id
            }
        } catch {
            print("saveNotes failed: \(error)")
        }
    }

    private func ensureWorkoutId(db: AppDatabase, sessionType: Workout.SessionType) async throws -> Int64 {
        if let id = workoutId { return id }
        let id = try await db.getOrCreateWorkout(on: date, sessionType: sessionType)
        workoutId = id
        return id
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    WorkoutsTab()
        .environment(\.appDatabase, try? AppDatabase.inMemory())
}
