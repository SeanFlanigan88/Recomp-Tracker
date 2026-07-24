import Foundation

// MARK: - Weekday

/// Days of the week keyed to `Calendar.component(.weekday, from:)`, which
/// returns 1 for Sunday through 7 for Saturday in the Gregorian calendar.
public enum Weekday: Int, CaseIterable, Sendable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var shortName: String {
        switch self {
        case .sunday:    return "Sun"
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        }
    }

    public var longName: String {
        switch self {
        case .sunday:    return "Sunday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        }
    }

    public static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        let raw = calendar.component(.weekday, from: date)
        return Weekday(rawValue: raw) ?? .monday
    }
}

// MARK: - ProgramExercise

/// A prescribed exercise in a program day. Stable `id` for view identity and
/// state keying; `name` is the human-facing label and also the natural key we
/// use to resolve the corresponding row in the `exercises` table.
public struct ProgramExercise: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let sets: Int
    /// Prescribed rep target, as free text — the source program uses ranges
    /// ("6–8"), times ("45 sec"), per-side counts ("10/leg"), and words
    /// ("max"). Free text preserves the intent without forcing us to model
    /// every variant.
    public let reps: String
    public let rest: String?
    public let isAnchor: Bool

    /// Category used when materializing the `exercises` row on first log.
    /// Anchor lifts get `.anchor` so PR detection surfaces them on the Log
    /// tab; everything else is `.accessory`.
    public var category: Exercise.Category {
        isAnchor ? .anchor : .accessory
    }

    public init(
        id: String,
        name: String,
        sets: Int,
        reps: String,
        rest: String? = nil,
        isAnchor: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.rest = rest
        self.isAnchor = isAnchor
    }
}

// MARK: - ProgramDay

public struct ProgramDay: Sendable, Hashable {
    public let name: String        // "Push", "Pull", "Rest"
    public let subtitle: String    // "Chest · Shoulders · Triceps"
    public let kind: Kind

    /// The session_type value to write on the `workouts` row when the user
    /// logs anything for this day. `nil` for pure rest days — no workout row
    /// is created for a rest day at all.
    public let sessionType: Workout.SessionType?

    public enum Kind: Sendable, Hashable {
        case rest(note: String)
        case cardio(note: String)
        case lifting(exercises: [ProgramExercise])
        case hybrid(cardioNote: String, exercises: [ProgramExercise])
    }

    public init(
        name: String,
        subtitle: String,
        sessionType: Workout.SessionType?,
        kind: Kind
    ) {
        self.name = name
        self.subtitle = subtitle
        self.sessionType = sessionType
        self.kind = kind
    }

    // MARK: Convenience accessors

    public var exercises: [ProgramExercise] {
        switch kind {
        case .rest, .cardio:                 return []
        case .lifting(let exs):              return exs
        case .hybrid(_, let exs):            return exs
        }
    }

    public var cardioNote: String? {
        switch kind {
        case .cardio(let note):              return note
        case .hybrid(let note, _):           return note
        case .rest, .lifting:                return nil
        }
    }

    public var restNote: String? {
        if case .rest(let note) = kind { return note }
        return nil
    }

    public var isRest: Bool {
        if case .rest = kind { return true }
        return false
    }

    public var hasCardio: Bool {
        switch kind {
        case .cardio, .hybrid: return true
        case .rest, .lifting:  return false
        }
    }
}

// MARK: - Program

public struct Program: Sendable, Hashable {
    public let name: String
    public let days: [Weekday: ProgramDay]

    public init(name: String, days: [Weekday: ProgramDay]) {
        self.name = name
        self.days = days
    }

    /// Day for a given date, falling back to a synthesized rest day if the
    /// weekday isn't defined in the program (shouldn't happen for cycle 2 —
    /// all seven days are populated — but keeps callers non-optional).
    public func day(for date: Date, calendar: Calendar = .current) -> ProgramDay {
        let weekday = Weekday.from(date: date, calendar: calendar)
        return days[weekday] ?? ProgramDay(
            name: "Rest",
            subtitle: "No plan for this day.",
            sessionType: nil,
            kind: .rest(note: "No program day defined.")
        )
    }
}

// MARK: - Cycle 2 (definitive source: docs archived from cycle2-tracker.html)

public extension Program {

    /// The cycle 2 program. Structure ported verbatim from
    /// `cycle2-tracker.html`'s WORKOUTS constant so anchor flags, set/rep
    /// prescriptions, and cardio notes match what Sean's used to.
    ///
    /// To modify the program: edit this constant and ship a new build. No
    /// migration path — cycle 3 will get its own constant and a runtime
    /// selection mechanism when that's actually a problem to solve.
    static let cycle2 = Program(
        name: "Cycle 2",
        days: [
            .sunday: ProgramDay(
                name: "Rest",
                subtitle: "Recovery · Weekly Check-In",
                sessionType: nil,
                kind: .rest(note: "Optional 30 min walk. Do this week's check-in in the Check-ins tab.")
            ),

            .monday: ProgramDay(
                name: "Push",
                subtitle: "Chest · Shoulders · Triceps",
                sessionType: .push,
                kind: .lifting(exercises: [
                    ProgramExercise(id: "bench",        name: "Barbell bench press",       sets: 4, reps: "6–8", rest: "2–3 min", isAnchor: true),
                    ProgramExercise(id: "incline-db",   name: "Incline dumbbell press",    sets: 3, reps: "10",  rest: "90 sec"),
                    ProgramExercise(id: "ohp",          name: "Standing barbell OHP",      sets: 3, reps: "8",   rest: "2 min"),
                    ProgramExercise(id: "cable-fly",    name: "Cable chest fly",           sets: 3, reps: "12",  rest: "60 sec"),
                    ProgramExercise(id: "lat-raise",    name: "Dumbbell lateral raise",    sets: 3, reps: "15",  rest: "60 sec"),
                    ProgramExercise(id: "tri-pushdown", name: "Tricep rope pushdown",      sets: 3, reps: "12",  rest: "60 sec"),
                    ProgramExercise(id: "tri-oh",       name: "Overhead tricep extension", sets: 3, reps: "12",  rest: "60 sec"),
                ])
            ),

            .tuesday: ProgramDay(
                name: "Zone 2 Cardio",
                subtitle: "40 min incline walk + mobility",
                sessionType: .cardio,
                kind: .cardio(note: "40 min at 12% incline, alternating 3 min @ 3.8 mph / 2 min @ 3.5 mph. Target HR 130–140. Follow with 15 min mobility.")
            ),

            .wednesday: ProgramDay(
                name: "Pull",
                subtitle: "Back · Biceps · Rear Delts",
                sessionType: .pull,
                kind: .lifting(exercises: [
                    ProgramExercise(id: "pulldown",    name: "Lat pulldown / weighted pull-up", sets: 4, reps: "8–10", rest: "2 min", isAnchor: true),
                    ProgramExercise(id: "bb-row",      name: "Barbell bent-over row",           sets: 4, reps: "8",    rest: "2 min"),
                    ProgramExercise(id: "cable-row",   name: "Seated cable row",                sets: 3, reps: "10",   rest: "90 sec"),
                    ProgramExercise(id: "face-pull",   name: "Face pull",                       sets: 3, reps: "15",   rest: "60 sec"),
                    ProgramExercise(id: "bb-curl",     name: "Barbell curl",                    sets: 3, reps: "10",   rest: "90 sec"),
                    ProgramExercise(id: "hammer",      name: "Dumbbell hammer curl",            sets: 3, reps: "12",   rest: "60 sec"),
                    ProgramExercise(id: "reverse-fly", name: "Reverse fly",                     sets: 3, reps: "15",   rest: "60 sec"),
                ])
            ),

            .thursday: ProgramDay(
                name: "Legs",
                subtitle: "Quads · Hamstrings · Glutes",
                sessionType: .legs,
                kind: .lifting(exercises: [
                    ProgramExercise(id: "squat",     name: "Barbell back squat",              sets: 4, reps: "6–8",           rest: "2–3 min", isAnchor: true),
                    ProgramExercise(id: "rdl-dl",    name: "RDL / Deadlift (alternate weekly)", sets: 3, reps: "8 RDL / 5 conv", rest: "2–3 min", isAnchor: true),
                    ProgramExercise(id: "leg-press", name: "Leg press",                       sets: 3, reps: "10–12",         rest: "90 sec"),
                    ProgramExercise(id: "lunge",     name: "Walking dumbbell lunges",         sets: 3, reps: "10/leg",        rest: "90 sec"),
                    ProgramExercise(id: "leg-curl",  name: "Lying leg curl",                  sets: 3, reps: "12",            rest: "60 sec"),
                    ProgramExercise(id: "calf",      name: "Standing calf raise",             sets: 4, reps: "15",            rest: "45 sec"),
                    ProgramExercise(id: "hlr",       name: "Hanging leg raise",               sets: 3, reps: "10",            rest: "60 sec"),
                ])
            ),

            .friday: ProgramDay(
                name: "Upper",
                subtitle: "Supersets · Higher Volume",
                sessionType: .upper,
                kind: .lifting(exercises: [
                    // Supersets 1a/1b, 2a/2b, etc. represented via the name
                    // prefix, matching the HTML tracker convention. Structural
                    // pairing (side-by-side render, paired rest timers) is in
                    // docs/backlog.md pending real-world use after Aug 3.
                    ProgramExercise(id: "incline-bb",   name: "1a · Incline barbell press",    sets: 3, reps: "10"),
                    ProgramExercise(id: "cs-row",       name: "1b · Chest-supported DB row",   sets: 3, reps: "12"),
                    ProgramExercise(id: "db-shoulder",  name: "2a · Seated DB shoulder press", sets: 3, reps: "10"),
                    ProgramExercise(id: "pullup-amrap", name: "2b · Pull-up (AMRAP)",          sets: 3, reps: "max"),
                    ProgramExercise(id: "db-fly",       name: "3a · Dumbbell fly",             sets: 3, reps: "12"),
                    ProgramExercise(id: "cable-rear",   name: "3b · Cable rear delt fly",      sets: 3, reps: "15"),
                    ProgramExercise(id: "db-curl",      name: "4a · Dumbbell curl",            sets: 3, reps: "12"),
                    ProgramExercise(id: "dip",          name: "4b · Tricep dip",               sets: 3, reps: "12"),
                ])
            ),

            .saturday: ProgramDay(
                name: "HIIT + Core",
                subtitle: "Metabolic · Abs",
                // .cardio because HIIT is the primary intent; the core work
                // is secondary volume. Session type is a categorical label,
                // not exclusive — core sets still land in exercise_sets.
                sessionType: .cardio,
                kind: .hybrid(
                    cardioNote: "HIIT 25 min: 2 min warm-up, 12 rounds of 30 sec sprint / 60 sec walk, 3 min cool-down.",
                    exercises: [
                        ProgramExercise(id: "plank",    name: "Plank hold",              sets: 3, reps: "45 sec"),
                        ProgramExercise(id: "hlr-sat",  name: "Hanging leg raise",       sets: 3, reps: "10"),
                        ProgramExercise(id: "bicycle",  name: "Bicycle crunch",          sets: 3, reps: "20"),
                        ProgramExercise(id: "twist",    name: "Russian twist (weighted)", sets: 3, reps: "20"),
                        ProgramExercise(id: "deadbug",  name: "Dead bug",                sets: 3, reps: "10/side"),
                    ]
                )
            ),
        ]
    )
}
