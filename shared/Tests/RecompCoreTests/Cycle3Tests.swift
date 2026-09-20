import XCTest
@testable import RecompCore

/// Tests for the Cycle 3 constant.
///
/// The constant is generated from the program JSON, so these are not spot
/// checks of transcription. They pin the rules that make it usable: that cues
/// are fully split out of names, that the same movement carries one name across
/// phases, and that the rotation resolves for any ordinal.
final class Cycle3Tests: XCTestCase {

    private let program = Program.cycle3

    // MARK: - Shape

    func testHasThreePhases() {
        XCTAssertEqual(program.phases.map(\.phase), [.one, .two, .three])
    }

    func testEveryPhaseHasAFullRotation() {
        for phase in Phase.allCases {
            let sessions = program.phase(phase).sessions
            XCTAssertEqual(sessions.count, Phase.rotationLength, "phase \(phase.rawValue)")
            XCTAssertEqual(
                sessions.map(\.slot),
                Array(1...Phase.rotationLength),
                "slots must be in order for phase \(phase.rawValue)"
            )
        }
    }

    func testEveryPhaseHasFiveLiftingAndTwoRecoverySessions() {
        for phase in Phase.allCases {
            let sessions = program.phase(phase).sessions
            XCTAssertEqual(sessions.filter(\.isLifting).count, 5, "phase \(phase.rawValue)")
            XCTAssertEqual(sessions.filter { !$0.isLifting }.count, 2, "phase \(phase.rawValue)")
        }
    }

    func testRecoverySlotsAreThreeAndSeven() {
        for phase in Phase.allCases {
            let recovery = program.phase(phase).sessions.filter { !$0.isLifting }.map(\.slot)
            XCTAssertEqual(recovery, [3, 7], "phase \(phase.rawValue)")
        }
    }

    func testRecoverySessionsStillCarryGuidance() {
        for phase in Phase.allCases {
            for session in program.phase(phase).sessions where !session.isLifting {
                XCTAssertFalse(
                    session.name.isEmpty,
                    "slot \(session.slot) in phase \(phase.rawValue) needs a name"
                )
                XCTAssertTrue(
                    session.detail != nil || session.cardio != nil,
                    "slot \(session.slot) in phase \(phase.rawValue) would render blank"
                )
            }
        }
    }

    func testMobilityFinisherIsShared() {
        XCTAssertEqual(program.mobilityFinisher.count, 4)
        XCTAssertEqual(program.mobilityFinisher.first?.name, "90/90 hip switch")
        XCTAssertFalse(program.mobilityFinisherDuration.isEmpty)
    }

    // MARK: - Canonicalization

    func testNoExerciseNameCarriesACue() {
        for phase in Phase.allCases {
            for session in program.phase(phase).sessions {
                for exercise in session.exercises {
                    XCTAssertFalse(
                        exercise.name.contains("("),
                        "\(exercise.name) still has its cue baked into the name"
                    )
                }
            }
        }
    }

    func testCuesAreSplitOutWhereThePrescriptionHadThem() {
        let dbRow = exercise(named: "DB row", phase: .one, slot: 5)
        XCTAssertEqual(dbRow?.cue, "bench-supported")

        let gobletP3 = exercise(named: "KB goblet squat", phase: .three, slot: 1)
        XCTAssertEqual(gobletP3?.cue, "max KB, pause at bottom")
    }

    func testGroupingPrefixIsStrippedFromAbCircuit() {
        let names = program.allExerciseNames
        XCTAssertFalse(names.contains { $0.hasPrefix("Ab circuit") })
        XCTAssertTrue(names.contains("Plank"))
        XCTAssertTrue(names.contains("Bicycle crunch"))
        XCTAssertTrue(names.contains("V-up"))
    }

    func testComplexPrefixIsKept() {
        // A complex swing runs at zero rest inside a chain; a standalone KB
        // swing is a 15-rep set. Merging them would make "last time" misleading.
        let names = program.allExerciseNames
        XCTAssertTrue(names.contains("KB complex: swing"))
        XCTAssertTrue(names.contains("KB swing"))
    }

    func testAliasedMovementsShareOneName() {
        // Each of these was written two different ways across phases.
        for (name, expected) in [
            ("KB complex: squat", [Phase.one, .two, .three]),
            ("KB complex: lunge", [Phase.one, .two, .three]),
            ("Dip", [Phase.two, .three]),
            ("Plank", [Phase.two, .three]),
            ("Step-up", [Phase.one, .three]),
            ("Standing calf raise", [Phase.one, .three]),
        ] {
            XCTAssertEqual(phases(containing: name), expected, name)
        }
    }

    func testAliasedNamesAreGoneEntirely() {
        let names = program.allExerciseNames
        for stale in [
            "KB complex: goblet squat",
            "KB complex: reverse lunge",
            "Bench dip",
            "Single-leg step-up",
            "Calf raise",
            "DB curl / Hammer curl",
        ] {
            XCTAssertFalse(names.contains(stale), "\(stale) should have been aliased away")
        }
    }

    func testAlternatingCurlIsTwoRows() {
        // Phase 3 Friday prescribes "DB curl / Hammer curl (alternate weekly)".
        // Kept as one combined name it would inherit no history from phases 1-2.
        let friday = program.phase(.three).session(slot: 5)
        let names = friday.exercises.map(\.name)
        XCTAssertTrue(names.contains("DB curl"))
        XCTAssertTrue(names.contains("Hammer curl"))

        XCTAssertEqual(phases(containing: "DB curl"), [.one, .two, .three])
        XCTAssertEqual(phases(containing: "Hammer curl"), [.one, .two, .three])
    }

    func testExerciseCountsMatchTheCanonicalisedProgram() {
        let names = program.allExerciseNames
        XCTAssertEqual(names.count, 47)

        let spanning = names.filter { phases(containing: $0).count > 1 }
        XCTAssertEqual(spanning.count, 29, "cross-phase history depends on this staying high")
    }

    // MARK: - Prescriptions

    func testEveryExerciseHasAUsablePrescription() {
        for phase in Phase.allCases {
            for session in program.phase(phase).sessions {
                for exercise in session.exercises {
                    XCTAssertGreaterThanOrEqual(exercise.sets, 1, exercise.name)
                    XCTAssertFalse(exercise.reps.isEmpty, exercise.name)
                    XCTAssertFalse(exercise.name.isEmpty)
                    XCTAssertNotEqual(exercise.cue, "", "empty cue should be nil, not blank")
                }
            }
        }
    }

    func testPrescriptionRendersAsALabel() {
        let goblet = exercise(named: "KB goblet squat", phase: .one, slot: 1)
        XCTAssertEqual(goblet?.prescription, "4 × 12-15")
    }

    // MARK: - Rotation

    func testSessionResolvesByOrdinal() {
        let first = program.session(phase: .one, ordinal: 1)
        XCTAssertEqual(first.slot, 1)

        let eighth = program.session(phase: .one, ordinal: 8)
        XCTAssertEqual(eighth, first, "ordinal 8 is the same session as ordinal 1")
    }

    func testSessionResolvesPastNominalPhaseLength() {
        let session = program.session(phase: .one, ordinal: 37)
        XCTAssertEqual(session.slot, 2)
        XCTAssertEqual(session, program.session(phase: .one, ordinal: 2))
    }

    func testEveryOrdinalInALongRunResolves() {
        for phase in Phase.allCases {
            for ordinal in 1...100 {
                let session = program.session(phase: phase, ordinal: ordinal)
                XCTAssertEqual(session.slot, Phase.slot(forOrdinal: ordinal))
            }
        }
    }

    // MARK: - Helpers

    private func exercise(named name: String, phase: Phase, slot: Int) -> ProgramExercise? {
        program.phase(phase).session(slot: slot).exercises.first { $0.name == name }
    }

    private func phases(containing name: String) -> [Phase] {
        Phase.allCases.filter { phase in
            program.phase(phase).sessions.contains { session in
                session.exercises.contains { $0.name == name }
            }
        }
    }
}
