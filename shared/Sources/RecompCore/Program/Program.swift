import Foundation

/// One prescribed movement within a session.
///
/// `name` is canonical and is what gets looked up in the `exercises` table —
/// it must match across phases or history stops carrying forward. `cue` holds
/// everything the JSON packed into parentheses ("bench-supported", "heavier KB
/// than Monday") plus any note, and is display text only.
///
/// `sets` and `reps` are the prescription, shown as a label beside the input.
/// Neither is persisted: one weight and one rep count cover every round.
public struct ProgramExercise: Hashable, Sendable {
    public let name: String
    public let cue: String?
    public let sets: Int

    /// Free text — "12-15", "10/side", "30-45 sec", "AMRAP", "20 yards".
    public let reps: String

    public init(name: String, cue: String? = nil, sets: Int, reps: String) {
        self.name = name
        self.cue = cue
        self.sets = sets
        self.reps = reps
    }

    /// The prescription as shown on the right of an exercise row, e.g. "4 × 12-15".
    public var prescription: String { "\(sets) × \(reps)" }
}

/// One movement in the mobility block appended to every training day.
public struct MobilityMove: Hashable, Sendable {
    public let name: String
    public let reps: String

    public init(name: String, reps: String) {
        self.name = name
        self.reps = reps
    }
}

/// One of the seven sessions in a phase's rotation.
public struct ProgramSession: Hashable, Sendable {

    /// 1-based position in the rotation.
    public let slot: Int

    public let name: String

    /// Cardio prescription for this session, if any. Not yet loggable —
    /// cardio is deferred, see docs/overhaul-plan.md.
    public let cardio: String?

    /// Prose for sessions with no loaded work (the two recovery days).
    public let detail: String?

    public let exercises: [ProgramExercise]

    public init(
        slot: Int,
        name: String,
        cardio: String? = nil,
        detail: String? = nil,
        exercises: [ProgramExercise]
    ) {
        self.slot = slot
        self.name = name
        self.cardio = cardio
        self.detail = detail
        self.exercises = exercises
    }

    /// False for the two recovery slots, which are still marked complete and
    /// still count toward the phase's 30.
    public var isLifting: Bool { !exercises.isEmpty }
}

/// One 30-session block, holding the seven sessions that repeat within it.
public struct ProgramPhase: Hashable, Sendable {
    public let phase: Phase
    public let name: String

    /// Exactly `Phase.rotationLength` sessions, in slot order.
    public let sessions: [ProgramSession]

    public init(phase: Phase, name: String, sessions: [ProgramSession]) {
        self.phase = phase
        self.name = name
        self.sessions = sessions
    }

    /// The session at a given 1-based slot.
    public func session(slot: Int) -> ProgramSession {
        precondition(
            (1...Phase.rotationLength).contains(slot),
            "slot out of range: \(slot)"
        )
        return sessions[slot - 1]
    }

    /// The session for a 1-based ordinal, wrapping through the rotation.
    /// Unbounded — ordinal 37 is as valid as ordinal 3.
    public func session(ordinal: Int) -> ProgramSession {
        session(slot: Phase.slot(forOrdinal: ordinal))
    }
}

/// A full training cycle: three phases plus the mobility block common to all.
public struct Program: Hashable, Sendable {
    public let name: String
    public let mobilityFinisherDuration: String
    public let mobilityFinisher: [MobilityMove]
    public let phases: [ProgramPhase]

    public init(
        name: String,
        mobilityFinisherDuration: String,
        mobilityFinisher: [MobilityMove],
        phases: [ProgramPhase]
    ) {
        self.name = name
        self.mobilityFinisherDuration = mobilityFinisherDuration
        self.mobilityFinisher = mobilityFinisher
        self.phases = phases
    }

    public func phase(_ phase: Phase) -> ProgramPhase {
        guard let match = phases.first(where: { $0.phase == phase }) else {
            preconditionFailure("program \(name) has no phase \(phase.rawValue)")
        }
        return match
    }

    /// The session to show for a phase and 1-based ordinal.
    public func session(phase: Phase, ordinal: Int) -> ProgramSession {
        self.phase(phase).session(ordinal: ordinal)
    }

    /// Every canonical exercise name in the cycle, deduplicated.
    ///
    /// This is the set that has to exist in the `exercises` table for history
    /// to carry across phases.
    public var allExerciseNames: Set<String> {
        Set(phases.flatMap { $0.sessions }.flatMap { $0.exercises }.map(\.name))
    }
}
