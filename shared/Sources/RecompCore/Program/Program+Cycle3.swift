import Foundation

// Generated from `90 day cycle part 2.json`, with the cue split and the
// exercise aliases applied. See `docs/overhaul-plan.md` for why names are
// canonicalized and `docs/program-aliases.md` for the alias table itself.
//
// Edited by hand only when the program changes. If a future cycle arrives,
// regenerate rather than patch.

public extension Program {

    static let cycle3 = Program(
        name: "Cycle 3 — General Fitness & Athleticism (Home KB/DB)",
        mobilityFinisherDuration: "5-8 min",
        mobilityFinisher: [
            MobilityMove(name: "90/90 hip switch", reps: "5/side"),
            MobilityMove(name: "World's greatest stretch", reps: "5/side"),
            MobilityMove(name: "Thoracic open-book", reps: "8/side"),
            MobilityMove(name: "Down dog to cobra flow", reps: "6"),
        ],
        phases: [
            ProgramPhase(
                phase: .one,
                name: "Foundation Expansion",
                sessions: [
                    ProgramSession(
                        slot: 1,
                        name: "Legs A - Quad/Posterior Chain",
                        cardio: "20 min Zone 2 treadmill",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB goblet squat", cue: nil, sets: 4, reps: "12-15"),
                            ProgramExercise(name: "DB Romanian deadlift", cue: nil, sets: 4, reps: "12-15"),
                            ProgramExercise(name: "Reverse lunge", cue: "DB, both hands", sets: 3, reps: "12/leg"),
                            ProgramExercise(name: "Step-up", cue: "bench, DB", sets: 3, reps: "12/leg"),
                            ProgramExercise(name: "KB swing", cue: nil, sets: 3, reps: "15"),
                            ProgramExercise(name: "Standing calf raise", cue: "bench edge", sets: 3, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 2,
                        name: "Push - single-arm OHP emphasis",
                        cardio: "jump rope 3x5 min",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB floor press", cue: nil, sets: 4, reps: "12-15"),
                            ProgramExercise(name: "Single-arm KB overhead press", cue: nil, sets: 3, reps: "10/side"),
                            ProgramExercise(name: "Incline DB press", cue: "bench", sets: 3, reps: "12-15"),
                            ProgramExercise(name: "Push-up", cue: "feet elevated on bench once bodyweight is easy", sets: 3, reps: "12-15"),
                            ProgramExercise(name: "Lateral raise", cue: "DB", sets: 3, reps: "15"),
                            ProgramExercise(name: "Overhead tricep extension", cue: "DB", sets: 3, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 3,
                        name: "Active Recovery + Mobility",
                        cardio: "30 min incline treadmill walk (3.5 mph, 8-10% grade)",
                        detail: "20-25 min yoga/mobility flow, no loading: cat-cow x10, hip flexor lunge stretch 60 sec/side, pigeon pose 60 sec/side, seated forward fold 60 sec, thread-the-needle 8/side, standing quad stretch 45 sec/side",
                        exercises: []
                    ),
                    ProgramSession(
                        slot: 4,
                        name: "Legs B - Glute/Hamstring",
                        cardio: "20 min Zone 2 treadmill",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB hip thrust", cue: "shoulders on bench", sets: 4, reps: "12-15"),
                            ProgramExercise(name: "Single-leg RDL", cue: "DB", sets: 3, reps: "12/side"),
                            ProgramExercise(name: "Curtsy lunge", cue: "DB", sets: 3, reps: "12/side"),
                            ProgramExercise(name: "Lateral lunge", cue: "KB goblet hold", sets: 3, reps: "12/side"),
                            ProgramExercise(name: "KB swing", cue: "heavier KB than Monday", sets: 3, reps: "15"),
                            ProgramExercise(name: "Standing calf raise", cue: nil, sets: 3, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 5,
                        name: "Pull + Core",
                        cardio: "jump rope 3x5 min",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB row", cue: "bench-supported", sets: 4, reps: "12-15"),
                            ProgramExercise(name: "KB clean", cue: nil, sets: 3, reps: "10/side"),
                            ProgramExercise(name: "Renegade row", cue: nil, sets: 3, reps: "10/side"),
                            ProgramExercise(name: "DB curl", cue: nil, sets: 3, reps: "15"),
                            ProgramExercise(name: "Hammer curl", cue: nil, sets: 3, reps: "15"),
                            ProgramExercise(name: "Dead bug", cue: nil, sets: 3, reps: "12/side"),
                            ProgramExercise(name: "Hollow hold", cue: nil, sets: 3, reps: "30 sec"),
                        ]
                    ),
                    ProgramSession(
                        slot: 6,
                        name: "Full-Body Conditioning",
                        cardio: "20 min Zone 2 treadmill",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB complex: swing", cue: "no rest within complex, 45 sec rest between rounds", sets: 5, reps: "6"),
                            ProgramExercise(name: "KB complex: clean", cue: nil, sets: 5, reps: "6"),
                            ProgramExercise(name: "KB complex: squat", cue: nil, sets: 5, reps: "6"),
                            ProgramExercise(name: "KB complex: press", cue: nil, sets: 5, reps: "6"),
                            ProgramExercise(name: "KB complex: lunge", cue: "reverse", sets: 5, reps: "6"),
                            ProgramExercise(name: "Turkish get-up", cue: "new movement, go light while learning", sets: 3, reps: "3/side"),
                        ]
                    ),
                    ProgramSession(
                        slot: 7,
                        name: "Active Recovery",
                        cardio: nil,
                        detail: "Easy walk 20-30 min (dog walk counts), long stretch 15-20 min (hamstrings, hip flexors, thoracic spine). No loading.",
                        exercises: []
                    ),
                ]
            ),
            ProgramPhase(
                phase: .two,
                name: "Build",
                sessions: [
                    ProgramSession(
                        slot: 1,
                        name: "Legs A",
                        cardio: "25 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB goblet squat", cue: "heavier KB", sets: 4, reps: "10-12"),
                            ProgramExercise(name: "DB Romanian deadlift", cue: nil, sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Bulgarian split squat", cue: "rear foot on bench, DB in hand", sets: 4, reps: "10/leg"),
                            ProgramExercise(name: "Walking lunge", cue: "DB", sets: 3, reps: "10/leg"),
                            ProgramExercise(name: "Nordic curl", cue: "or slow eccentric single-leg RDL if no foot anchor", sets: 3, reps: "8"),
                        ]
                    ),
                    ProgramSession(
                        slot: 2,
                        name: "Push + Shoulders (superset block)",
                        cardio: "HIIT - 10x30 sec sprint / 60 sec walk",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB bench press", cue: nil, sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Push-up", cue: "feet elevated", sets: 4, reps: "AMRAP"),
                            ProgramExercise(name: "Single-arm KB overhead press", cue: nil, sets: 4, reps: "8/side"),
                            ProgramExercise(name: "Lateral raise", cue: "DB", sets: 4, reps: "12"),
                            ProgramExercise(name: "Dip", cue: "bench", sets: 3, reps: "12"),
                            ProgramExercise(name: "Overhead tricep extension", cue: "DB", sets: 3, reps: "12"),
                            ProgramExercise(name: "Rear delt fly", cue: "DB", sets: 3, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 3,
                        name: "Active Recovery + Mobility (expanded)",
                        cardio: "35 min incline treadmill walk",
                        detail: "25-30 min yoga flow (Phase 1 flow plus: low lunge with twist 6/side, half-split stretch 60 sec/side, frog stretch 60 sec, spinal twist 45 sec/side). Foam roll/tennis ball if available.",
                        exercises: []
                    ),
                    ProgramSession(
                        slot: 4,
                        name: "Legs B - Glute/Hamstring",
                        cardio: "25 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB hip thrust", cue: nil, sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Single-leg RDL", cue: "DB", sets: 4, reps: "10/side"),
                            ProgramExercise(name: "Single-arm suitcase carry", cue: "heavy KB, 40 ft", sets: 3, reps: "2 lengths/side"),
                            ProgramExercise(name: "Curtsy lunge", cue: "DB, heavier", sets: 3, reps: "10/side"),
                            ProgramExercise(name: "KB swing", cue: nil, sets: 4, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 5,
                        name: "Pull + Arms (superset block) + Core",
                        cardio: "jump rope 4x5 min",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB row", cue: "heavy", sets: 4, reps: "10"),
                            ProgramExercise(name: "KB clean", cue: nil, sets: 4, reps: "8/side"),
                            ProgramExercise(name: "Renegade row", cue: nil, sets: 3, reps: "10/side"),
                            ProgramExercise(name: "DB curl", cue: nil, sets: 3, reps: "12"),
                            ProgramExercise(name: "Hammer curl", cue: nil, sets: 3, reps: "12"),
                            ProgramExercise(name: "Plank", cue: "weighted - DB on back if stable", sets: 3, reps: "45 sec"),
                            ProgramExercise(name: "Weighted Russian twist", cue: "DB or KB", sets: 3, reps: "15/side"),
                        ]
                    ),
                    ProgramSession(
                        slot: 6,
                        name: "Full-Body AMRAP + Athleticism",
                        cardio: "25 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB complex: swing", cue: nil, sets: 6, reps: "6"),
                            ProgramExercise(name: "KB complex: clean", cue: nil, sets: 6, reps: "6"),
                            ProgramExercise(name: "KB complex: squat", cue: nil, sets: 6, reps: "6"),
                            ProgramExercise(name: "KB complex: press", cue: nil, sets: 6, reps: "6"),
                            ProgramExercise(name: "KB complex: lunge", cue: nil, sets: 6, reps: "6"),
                            ProgramExercise(name: "Lateral bounds", cue: nil, sets: 3, reps: "8/side"),
                            ProgramExercise(name: "Bear crawl", cue: nil, sets: 3, reps: "20 yards"),
                            ProgramExercise(name: "Jump rope", cue: "double-unders or fast singles", sets: 3, reps: "30 sec"),
                        ]
                    ),
                    ProgramSession(
                        slot: 7,
                        name: "Active Recovery + Weigh-in (optional)",
                        cardio: nil,
                        detail: "35 min walk, deep stretch 20 min.",
                        exercises: []
                    ),
                ]
            ),
            ProgramPhase(
                phase: .three,
                name: "Peak Density",
                sessions: [
                    ProgramSession(
                        slot: 1,
                        name: "Legs A (heaviest of the cycle)",
                        cardio: "30 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB goblet squat", cue: "max KB, pause at bottom", sets: 5, reps: "8-10"),
                            ProgramExercise(name: "DB Romanian deadlift", cue: nil, sets: 5, reps: "8-10"),
                            ProgramExercise(name: "Bulgarian split squat", cue: nil, sets: 4, reps: "8/leg"),
                            ProgramExercise(name: "Step-up", cue: "bench, single-leg", sets: 4, reps: "8/leg"),
                            ProgramExercise(name: "KB swing", cue: "heaviest", sets: 4, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 2,
                        name: "Push + Core (max effort)",
                        cardio: "HIIT - 12x30 sec sprint / 45 sec rest",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB bench press", cue: nil, sets: 5, reps: "8-10"),
                            ProgramExercise(name: "Single-arm KB overhead press", cue: "half-kneeling", sets: 4, reps: "8/side"),
                            ProgramExercise(name: "Push-up", cue: "weighted - DB on back or feet elevated", sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Dip", cue: "bench", sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Plank", cue: nil, sets: 3, reps: "45 sec"),
                            ProgramExercise(name: "Bicycle crunch", cue: nil, sets: 3, reps: "20"),
                            ProgramExercise(name: "V-up", cue: nil, sets: 3, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 3,
                        name: "Active Recovery + Mobility",
                        cardio: "40 min incline treadmill walk",
                        detail: "Full mobility flow combining Phase 1 and Phase 2 stretches, ~30 min. Ice/rest anything sore.",
                        exercises: []
                    ),
                    ProgramSession(
                        slot: 4,
                        name: "Legs B - Glute/Hamstring max",
                        cardio: "30 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB hip thrust", cue: "heavy", sets: 5, reps: "10"),
                            ProgramExercise(name: "Single-leg RDL", cue: nil, sets: 5, reps: "10/side"),
                            ProgramExercise(name: "Single-arm overhead carry", cue: "KB", sets: 4, reps: "2 lengths/side"),
                            ProgramExercise(name: "Curtsy lunge", cue: "heavy DB", sets: 4, reps: "10/side"),
                            ProgramExercise(name: "Standing calf raise", cue: nil, sets: 4, reps: "15"),
                        ]
                    ),
                    ProgramSession(
                        slot: 5,
                        name: "Pull Max + Core",
                        cardio: "HIIT - 12x30 sec sprint / 45 sec rest",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "DB row", cue: "max", sets: 5, reps: "8-10"),
                            ProgramExercise(name: "KB clean & press", cue: "single-arm", sets: 4, reps: "8/side"),
                            ProgramExercise(name: "Renegade row", cue: nil, sets: 4, reps: "10/side"),
                            ProgramExercise(name: "DB curl", cue: "alternate weekly with hammer curl", sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Hammer curl", cue: "alternate weekly with DB curl", sets: 4, reps: "10-12"),
                            ProgramExercise(name: "Hollow hold", cue: nil, sets: 4, reps: "30-45 sec"),
                        ]
                    ),
                    ProgramSession(
                        slot: 6,
                        name: "Full-Body Max AMRAP + Athleticism",
                        cardio: "30 min Zone 2",
                        detail: nil,
                        exercises: [
                            ProgramExercise(name: "KB complex: swing", cue: nil, sets: 8, reps: "6"),
                            ProgramExercise(name: "KB complex: clean", cue: nil, sets: 8, reps: "6"),
                            ProgramExercise(name: "KB complex: squat", cue: nil, sets: 8, reps: "6"),
                            ProgramExercise(name: "KB complex: press", cue: nil, sets: 8, reps: "6"),
                            ProgramExercise(name: "KB complex: lunge", cue: nil, sets: 8, reps: "6"),
                            ProgramExercise(name: "KB complex: windmill", cue: "new movement, closes complex", sets: 8, reps: "6"),
                            ProgramExercise(name: "Skater hops", cue: nil, sets: 3, reps: "10/side"),
                            ProgramExercise(name: "Bear crawl", cue: nil, sets: 3, reps: "25 yards"),
                            ProgramExercise(name: "Turkish get-up", cue: "heavier KB than Phase 1 if form is solid", sets: 4, reps: "4/side"),
                        ]
                    ),
                    ProgramSession(
                        slot: 7,
                        name: "Recovery + Weekly Review",
                        cardio: nil,
                        detail: "40 min walk, 30 min deep stretch. Review week: where reps stalled, where a variant needs to get harder.",
                        exercises: []
                    ),
                ]
            ),
        ]
    )
}
