# Data Schema

Full data model for Recomp Tracker. Three tables, eleven columns.

The app does one thing: show the prescribed session, let me log what weight and
reps I actually did, and show me what I did last time so I can decide whether to
go up. Everything in here serves that sentence. See `docs/overhaul-plan.md` for
the design this replaced and why.

## Design principles

1. **Identity is position, not date.** A session is `(phase, ordinal)`. Sessions
   are ordered by where they fall in the cycle, and doing the "Monday" workout on
   a Thursday is a non-event. The program's weekday names are source ordering
   only and never reach the database.
2. **One date, recorded at completion.** `completed_at` is the only date in the
   schema. It is NULL until the session is marked complete. Its one job is
   ordering the "last time" lookup.
3. **One row per exercise per session.** No `set_number`. One weight and one rep
   count cover every round — the weight does not change mid-session, only between
   weeks.
4. **Canonical exercise names.** Coaching cues are split off at ingestion and
   live on the program, not in `exercises.name`. This is what makes history span
   phases.
5. **Constraints in the schema, not just in Swift.** Uniqueness, foreign keys and
   CHECKs are declared here so that an illegal row cannot be written by any
   route.

## Tables

### `workouts`

One session of the cycle.

    id            INTEGER PRIMARY KEY
    phase         INTEGER NOT NULL      -- 1, 2, 3
    ordinal       INTEGER NOT NULL      -- 1-based, unbounded
    completed_at  DATETIME              -- NULL = pending

    UNIQUE(phase, ordinal)
    CHECK(phase BETWEEN 1 AND 3)
    CHECK(ordinal >= 1)
    INDEX on completed_at

`ordinal` has **no upper bound**. Each phase is nominally 30 sessions, but that
number is the denominator in a counter, not a limit. A phase reading `37/30` is a
valid, expected state — it means the block has run past its nominal length.

The session's content is derived, never stored:

    slot = ((ordinal - 1) mod 7) + 1

Slot 1 is the first session in the phase's rotation, slot 7 the last. Over 30
ordinals that gives four full rotations plus slots 1 and 2 — 22 lifting sessions
and 8 recovery sessions.

`session_type`, `duration_min`, `avg_hr`, `notes`, `started_at`/`ended_at` and the
HealthKit columns are all gone. Session type is derivable from `ordinal`; the rest
belonged to features that no longer exist.

### `exercises`

A movement, identified by its canonical name.

    id    INTEGER PRIMARY KEY
    name  TEXT NOT NULL UNIQUE

    CHECK(length(trim(name)) > 0)

**The name must be free of coaching cues.** The program JSON writes
`KB goblet squat`, `KB goblet squat (heavier KB)` and
`KB goblet squat (max KB, pause at bottom)` for one movement across three phases.
69 distinct name strings in the cycle collapse to 54 actual exercises, and 26 of
those appear in two or more phases.

Since `name` is UNIQUE and is the join key behind the "last time" lookup,
ingesting the strings verbatim would give the Phase 3 goblet squat no history
against the Phase 1 one — silently hiding exactly the numbers the app exists to
show. The parenthetical splits off at ingestion onto the program's `cue`.

`category`, `primary_muscle_group`, `movement_pattern`, `is_bilateral` and
`is_custom` were never populated meaningfully and are gone.

### `exercise_logs`

What was actually lifted.

    id           INTEGER PRIMARY KEY
    workout_id   INTEGER NOT NULL  -> workouts(id)   ON DELETE CASCADE
    exercise_id  INTEGER NOT NULL  -> exercises(id)  ON DELETE RESTRICT
    weight_lb    REAL
    reps         INTEGER

    UNIQUE(workout_id, exercise_id)
    CHECK(weight_lb IS NULL OR weight_lb >= 0)
    CHECK(reps IS NULL OR reps >= 0)
    INDEX on workout_id, exercise_id

`weight_lb` is NULL for bodyweight and unloaded work (hollow hold, bear crawl,
push-ups). Zero is permitted and distinct from NULL.

**`reps` carries whatever unit the prescription implies** — reps, reps per side,
seconds, or yards — with no discriminator column:

| Prescription | Example | In the cycle | `reps` holds |
|---|---|---:|---|
| plain | `12` | 38 | reps |
| range | `12-15` | 18 | reps achieved |
| per-side | `10/side`, `12/leg` | 30 | reps per side |
| timed | `30-45 sec` | 5 | seconds |
| distance | `20 yards` | 2 | yards |
| AMRAP | `AMRAP` | 1 | reps achieved |

This is safe **only because nothing computes on the number**. e1RM, top-set
detection and PR tracking were removed; a 45-second hollow hold and a 20-yard bear
crawl never enter arithmetic that would make the mixed units wrong. If any math
over `reps` is reintroduced, this decision has to be reopened first.

The cascade/restrict split is deliberate: deleting a session should take its logs
with it, while deleting an exercise that has history should fail loudly rather
than erase it.

## Migrations

Forward-only. `M001` was rewritten in place once, during the Cycle 3 overhaul —
no data was being preserved and `AppMigrator` sets `eraseDatabaseOnSchemaChange`
under DEBUG, so local databases rebuild on next launch. Normal rules resume from
there: never edit a shipped migration; add `M002`.
