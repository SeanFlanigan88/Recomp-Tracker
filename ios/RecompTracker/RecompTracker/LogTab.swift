import SwiftUI
import RecompCore

/// The Log tab: a single form covering everything Sean logs on a normal day.
///
/// Fields commit independently as they lose focus / on stepper release / on
/// button tap, rather than through a "Save today" button. Rationale in the
/// design conversation: matches how you'd actually use the app through the
/// day (weigh in morning, calories after dinner, notes at night) and there's
/// no did-I-remember-to-save failure mode.
///
/// Field → table:
///   Weight       → body_metrics.weight_lb (source = .manual, upsert per day)
///   Sleep 1–10   → daily_log.sleep_quality_1_10
///   Calories     → nutrition_log.kcal
///   Water        → nutrition_log.water_oz
///   Session      → derived from workouts row for today (read-only)
///   Anchor sets  → derived from exercise_sets JOIN exercises WHERE anchor
///   Notes        → daily_log.notes
struct LogTab: View {

    // MARK: - Injected

    @Environment(\.appDatabase) private var appDatabase: AppDatabase?

    /// Injected via init. Defaults to the real `HealthKitClient` in the app;
    /// tests and previews can pass a fake. Held as `let` so it isn't
    /// re-instantiated on view updates.
    private let healthKit: HealthKitReading

    init(
        onOpenWorkouts: @escaping () -> Void,
        healthKit: HealthKitReading = HealthKitClient()
    ) {
        self.onOpenWorkouts = onOpenWorkouts
        self.healthKit = healthKit
    }

    /// Called when the user taps the Session row. The Log tab doesn't know
    /// how it's hosted; ContentView routes this to the Workouts tab.
    let onOpenWorkouts: () -> Void

    // MARK: - Editable state
    //
    // Nil = "never set for today." First user interaction on a field flips
    // it to a concrete value and fires an upsert; until then, nothing about
    // that field lands in the database.

    @State private var weightLb: Double?
    @State private var sleepQuality: Int?
    @State private var kcal: Int?
    @State private var waterOz: Int = 0
    @State private var notes: String = ""

    // MARK: - Read-only state

    @State private var session: DailySessionSummary?
    @State private var anchorSets: [AnchorTopSetSummary] = []

    // MARK: - Housekeeping

    /// Guards against `.task` re-running load and clobbering user edits if
    /// the view remounts.
    @State private var didInitialLoad = false

    /// Non-nil = HealthKit handshake failed (authorization or read query).
    /// Rendered as a small dismissible banner near the top of the form.
    /// Manual entry keeps working regardless — this is informational.
    @State private var healthKitStatusMessage: String?

    @FocusState private var focusedField: Field?
    private enum Field: Hashable {
        case weight
        case kcal
        case notes
    }

    /// Captured at view mount. Not reactive to midnight rollover — acceptable
    /// for MVP; a session that spans midnight is a real edge case but rare
    /// and easily fixed by relaunching.
    private let date = Date()

    private static let waterGoalOz = 120
    private static let waterIncrementOz = 8

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if let message = healthKitStatusMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    weightRow
                    sleepRow
                    caloriesRow
                    waterRow
                    sessionRow
                }

                if !anchorSets.isEmpty {
                    Section("Anchor Lifts") {
                        ForEach(anchorSets, id: \.exerciseId) { anchorSetRow($0) }
                    }
                }

                Section("Notes") {
                    TextField("Daily reflection", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle(dateTitle)
            .keyboardDoneToolbar()
            .task {
                guard !didInitialLoad else { return }
                await loadEverything()
                await bootstrapHealthKit()
                didInitialLoad = true
            }
            .onAppear {
                // Cheap refresh so a workout logged on the Workouts tab shows
                // up when the user comes back here.
                guard didInitialLoad else { return }
                Task { await refreshWorkoutData() }
            }
            .onChange(of: focusedField) { oldValue, _ in
                // A field just lost focus — persist whatever's in state.
                Task { await saveOnFocusLoss(from: oldValue) }
            }
        }
    }

    // MARK: - Rows

    private var weightRow: some View {
        HStack {
            Text("Weight")
            Spacer()
            TextField("—",
                      value: $weightLb,
                      format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .weight)
                .submitLabel(.done)
                .onSubmit { Task { await saveWeight() } }
            Text("lb")
                .foregroundStyle(.secondary)
        }
    }

    private var sleepRow: some View {
        Stepper(
            value: Binding<Int>(
                // First tap from an unset state resolves to 5 as a neutral
                // starting anchor. Getter also drives the stepper's own
                // enabled/disabled bounds check.
                get: { sleepQuality ?? 5 },
                set: { newValue in
                    sleepQuality = newValue
                    Task { await saveSleep(newValue) }
                }
            ),
            in: 1...10
        ) {
            HStack {
                Text("Sleep")
                Spacer()
                Text(sleepQuality.map(String.init) ?? "—")
                    .foregroundStyle(sleepQuality == nil ? .secondary : .primary)
                    .monospacedDigit()
            }
        }
    }

    private var caloriesRow: some View {
        HStack {
            Text("Calories")
            Spacer()
            TextField("—", value: $kcal, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .kcal)
                .submitLabel(.done)
                .onSubmit { Task { await saveCalories() } }
            Text("kcal")
                .foregroundStyle(.secondary)
        }
    }

    private var waterRow: some View {
        HStack {
            Text("Water")
            Spacer()
            Text("\(waterOz) / \(Self.waterGoalOz) oz")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                let newValue = waterOz + Self.waterIncrementOz
                waterOz = newValue
                Task { await saveWater(newValue) }
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(Self.waterIncrementOz) ounces")
        }
    }

    private var sessionRow: some View {
        Button(action: onOpenWorkouts) {
            HStack {
                Text("Session")
                    .foregroundStyle(.primary)
                Spacer()
                Text(sessionLabel)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func anchorSetRow(_ s: AnchorTopSetSummary) -> some View {
        HStack {
            Text(s.exerciseName)
            Spacer()
            Text("\(formatWeight(s.weightLb)) × \(s.reps)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if s.isPR {
                Text("PR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Labels

    private var dateTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    private var sessionLabel: String {
        guard let s = session else { return "Not logged" }
        let type = s.sessionType.map { $0.rawValue.capitalized } ?? "Workout"
        if let mins = s.durationMin {
            return "\(type) · \(mins) min"
        }
        return type
    }

    private func formatWeight(_ w: Double) -> String {
        if w == w.rounded() {
            return String(Int(w))
        }
        return String(format: "%.1f", w)
    }

    // MARK: - Load

    private func loadEverything() async {
        guard let db = appDatabase else { return }
        do {
            async let dl = db.dailyLog(on: date)
            async let nl = db.nutritionLog(on: date)
            async let weight = db.todaysDisplayWeight(on: date)
            async let sess = db.todaysSession(on: date)
            async let anchors = db.anchorTopSets(on: date)

            if let dl = try await dl {
                sleepQuality = dl.sleepQuality
                notes = dl.notes ?? ""
            }
            if let nl = try await nl {
                kcal = nl.kcal
                waterOz = nl.waterOz ?? 0
            }
            weightLb = try await weight
            session = try await sess
            anchorSets = try await anchors
        } catch {
            // v1: log to console. When we have real observability, surface
            // a user-visible error state on the failing row.
            print("LogTab load failed: \(error)")
        }
    }

    private func refreshWorkoutData() async {
        guard let db = appDatabase else { return }
        do {
            async let sess = db.todaysSession(on: date)
            async let anchors = db.anchorTopSets(on: date)
            session = try await sess
            anchorSets = try await anchors
        } catch {
            print("LogTab workout refresh failed: \(error)")
        }
    }

    /// Ask HealthKit for read authorization, pull the last 30 days of samples
    /// for our scope-b types, import them (idempotent via UUID dedup), and
    /// refresh the weight display.
    ///
    /// Silent no-op on platforms where HealthKit isn't available (e.g.,
    /// simulator on macOS build). Handshake failures — authorization throws,
    /// or a sample query throws — surface via `healthKitStatusMessage` as a
    /// small banner. Empty read results are not an error: HK deliberately
    /// hides read-denials, so "no data" is indistinguishable from "denied"
    /// and both are handled the same way (display stays as manual entry).
    private func bootstrapHealthKit() async {
        guard let db = appDatabase else { return }
        guard healthKit.isHealthDataAvailable else { return }

        do {
            try await healthKit.requestReadAuthorization()

            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                ?? Date.distantPast
            var collected: [QuantitySampleImport] = []
            for kind in QuantitySampleImport.Kind.allCases {
                let samples = try await healthKit.quantitySamples(kind: kind, since: thirtyDaysAgo)
                collected.append(contentsOf: samples)
            }
            _ = try await db.importHealthKitSamples(collected)

            // Refresh only the weight — other metrics live on the Metrics tab
            // and load themselves when that tab opens.
            weightLb = try await db.todaysDisplayWeight(on: date)
            healthKitStatusMessage = nil
        } catch {
            healthKitStatusMessage = "Health couldn't sync. Manual entry still works — try again next time you open the app."
            print("HK bootstrap failed: \(error)")
        }
    }

    // MARK: - Save

    private func saveOnFocusLoss(from previous: Field?) async {
        switch previous {
        case .weight: await saveWeight()
        case .kcal:   await saveCalories()
        case .notes:  await saveNotes()
        case .none:   break
        }
    }

    private func saveWeight() async {
        guard let db = appDatabase, let w = weightLb else { return }
        do {
            try await db.upsertTodaysManualWeight(w, on: date)
        } catch {
            print("saveWeight failed: \(error)")
        }
    }

    private func saveSleep(_ value: Int) async {
        guard let db = appDatabase else { return }
        do {
            try await db.upsertDailyLog(on: date) { $0.sleepQuality = value }
        } catch {
            print("saveSleep failed: \(error)")
        }
    }

    private func saveCalories() async {
        guard let db = appDatabase, let k = kcal else { return }
        do {
            try await db.upsertNutritionLog(on: date) { $0.kcal = k }
        } catch {
            print("saveCalories failed: \(error)")
        }
    }

    private func saveWater(_ value: Int) async {
        guard let db = appDatabase else { return }
        do {
            try await db.upsertNutritionLog(on: date) { $0.waterOz = value }
        } catch {
            print("saveWater failed: \(error)")
        }
    }

    private func saveNotes() async {
        guard let db = appDatabase else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await db.upsertDailyLog(on: date) {
                $0.notes = trimmed.isEmpty ? nil : trimmed
            }
        } catch {
            print("saveNotes failed: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    LogTab(onOpenWorkouts: {})
        .environment(\.appDatabase, try? AppDatabase.inMemory())
}
