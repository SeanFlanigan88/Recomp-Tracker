# Overhaul Plan — Cycle 3 Rebuild

**Status:** implemented — all five commits landed 2026-09-20
**Written:** 2026-09-16

---

## Why

The app was built to track body recomposition across five domains: workouts, body
composition, daily wellness, nutrition, and progress photos. Four of those are no
longer wanted. Training also moved from a gym to home kettlebell/dumbbell work on a
new 90-day program (`90 day cycle part 2.json`).

The app is being stripped to a single purpose:

> **Show me the prescribed workout, let me log what weight and reps I actually did, and
> show me what I did last time so I can decide in the moment whether to go up.**

Everything that does not serve that sentence is removed. This is not a feature freeze —
it is a deletion. Roughly 5,000 of 7,377 lines of Swift go away.

**The governing rule for this rebuild:** if something isn't necessary, flag it and remove
it. This applies to features not yet discussed, not just the ones in scope today.

---

## What the app is now

Two screens.

### Home

Three stacked blocks, Phase 1 on top through Phase 3 on the bottom.

```
        Phase 1
        12/30 sessions complete

        Phase 2
        0/30 sessions complete

        Phase 3
        0/30 sessions complete
```

Tapping a block opens the session detail for that phase. Any phase is tappable at any
time — there is no unlock, no gate, no active-phase concept. Moving to Phase 2 is you
deciding to tap Phase 2.

The counter is a reference display, not a boundary. **`x` may exceed 30** and that is
fine and intentional — `37/30` just means you have run past the nominal phase length.
There is no terminal state, no completion logic, and no bounds check anywhere.

### Session detail

```
        ‹ Back                                Session 5 of 30

        Pull + Core
        ────────────────────────────────────────────────
        DB row                                 4 × 12-15
        bench-supported
        [   55   ] lb        [   12   ] reps

        KB clean                               3 × 10/side
        [   40   ] lb        [   10   ] reps

        ...
        ────────────────────────────────────────────────
        Mobility finisher · 5-8 min
        90/90 hip switch 5/side · World's greatest stretch
        5/side · Thoracic open-book 8/side · Down dog to
        cobra flow 6
        ────────────────────────────────────────────────
                        [ Mark Complete ]

                          ‹ prev   next ›
```

- Exercise name is the **canonical** name. The cue (`bench-supported`,
  `heavier KB than Monday`) renders beneath in secondary text and is never part of
  identity. See [Exercise name canonicalization](#exercise-name-canonicalization).
- The prescription on the right (`4 × 12-15`) is a **display label only**. Set counts
  are not persisted.
- Two inputs per exercise. Ghosted with last time's numbers.
- Mobility finisher is a static footer on every training day. Nothing logged.
- `prev` / `next` walk ordinals in both directions, unbounded. Use `prev` to fix an
  accidental Mark Complete — completion is a toggle, not a one-way door.
- Back returns to Home.

---

## Session resolution

Tapping a phase block resolves to **the lowest ordinal in that phase with
`completed_at IS NULL`**, computed at read time.

There is no stored pointer and no advancement logic. Nothing to drift, nothing to
repair.

### The 7-slot rotation

Sessions are ordered by **position in the cycle, not by calendar day**. The JSON's
weekday names are only the source ordering; they are not shown in the UI and carry no
meaning at runtime. If you do the "Monday" session on a Wednesday, it is still session 1.

```
slot = ((ordinal - 1) mod 7) + 1
```

Phase 1's slots (same shape in all three phases):

| Slot | Session | Exercises |
|-----:|---------|----------:|
| 1 | Legs A — Quad/Posterior Chain | 6 |
| 2 | Push — single-arm OHP emphasis | 6 |
| 3 | Active Recovery + Mobility | 0 |
| 4 | Legs B — Glute/Hamstring | 6 |
| 5 | Pull + Core | 7 |
| 6 | Full-Body Conditioning | 6 |
| 7 | Active Recovery | 0 |

Over 30 ordinals: 4 full rotations plus slots 1 and 2 — **22 lifting sessions and
8 recovery sessions**.

Slots 3 and 7 have no exercises. They render as description text plus a Mark Complete
button, and **they count toward the 30**. Cardio entry for these lands later
(see [Deferred](#deferred)).

Slot is always computed, never stored.

---

## Schema

Three tables, eleven columns. Down from eight tables.

```sql
workouts
  id            INTEGER PK
  phase         INTEGER NOT NULL          -- 1, 2, 3
  ordinal       INTEGER NOT NULL          -- 1..n, unbounded
  completed_at  DATETIME NULL             -- NULL = pending; doubles as the date
  UNIQUE(phase, ordinal)

exercises
  id            INTEGER PK
  name          TEXT NOT NULL             -- canonical, cue stripped
  UNIQUE(name)

exercise_logs
  id            INTEGER PK
  workout_id    INTEGER NOT NULL FK -> workouts(id)
  exercise_id   INTEGER NOT NULL FK -> exercises(id)
  weight_lb     REAL NULL
  reps          INTEGER NULL
  UNIQUE(workout_id, exercise_id)
```

### No per-set rows

One weight and one rep count cover **every round** of an exercise in a session. The
weight does not change mid-session — it is one bell or one pair of dumbbells you do not
put down — and it only goes up the following week.

So `set_number` does not exist and `exercise_sets` is gone, replaced by one
`exercise_logs` row per (workout, exercise).

This is the single largest usability win in the rebuild:

| | per-set | per-exercise |
|---|---:|---:|
| Phase 3 Saturday | 116 boxes | 18 boxes |
| Phase 2 Saturday | 78 | 16 |
| All 3 phases, one rotation | **760** | **188** |

### `reps` carries whatever the prescription implies

`reps` is a plain integer holding the number you type. The unit comes from the
prescription label beside the field:

| Prescription kind | Example | Count | What goes in `reps` |
|---|---|---:|---|
| plain | `12` | 38 | reps |
| range | `12-15` | 18 | reps achieved |
| per-side | `10/side`, `12/leg` | 30 | reps per side |
| timed | `30-45 sec` | 5 | seconds |
| distance | `20 yards` | 2 | yards |
| AMRAP | `AMRAP` | 1 | reps achieved |

No unit discriminator column. This works **only because e1RM and PR detection are
gone** — there is no math consuming the number, so mixed units never collide.

For bodyweight and timed work, `weight_lb` stays NULL.

### `completed_at` is the only date

The date is recorded when a session is marked complete and is irrelevant before that.
One nullable column serves as both the completion flag and the timestamp.

It exists for exactly one reason: ordering the "last time" lookup.

---

## The "last time" lookup

This is the primary read path. It is **per exercise, not per session**:

> For exercise X, find the most recent workout by `completed_at` that has an
> `exercise_logs` row for X with a non-null `weight_lb`, and return that row.

Per-exercise rather than per-session is deliberate — it **spans phases**. When you reach
Phase 2's Monday goblet squat, you see your Phase 1 goblet squat numbers, not a blank
field.

Rendered as a placeholder in the weight and reps fields. No history screen, no charts,
no progress view.

---

## Exercise name canonicalization

**This is load-bearing for the feature above. It must happen at ingestion.**

The JSON bakes coaching cues into exercise names. 69 distinct name strings collapse to
**54 actual exercises**, and **26 of those 54 appear in two or more phases**.

```
KB goblet squat
KB goblet squat (heavier KB)
KB goblet squat (max KB, pause at bottom)

DB row (bench-supported)
DB row (heavy)
DB row (max)

KB swing
KB swing (heavier KB than Monday)
KB swing (heaviest)
```

`exercises.name` is UNIQUE and lookup is exact-match. Ingested verbatim, these become
separate rows with separate histories — and the Phase 3 goblet squat would show you
nothing, which defeats the entire remaining purpose of the app.

**Fix:** `ProgramExercise` gains `cue: String?`. The parenthetical splits off the name at
ingestion. Canonical name is the identity and the join key; cue is display text.

---

## What gets removed

`git rm` — 33 files, 4,997 lines:

**iOS target**
```
CheckInsTab.swift
LogTab.swift
Export/WeekExportWriter.swift
Health/HealthKitClient.swift
Photos/                          (all 7 files)
```

**RecompCore**
```
Export/Week.swift
Export/WeekExport.swift
Health/HealthKitReading.swift
Models/BodyMetric.swift
Models/CheckIn.swift
Models/DailyLog.swift
Models/NutritionLog.swift
Models/ProgressPhoto.swift
Queries/BodyMetricsSnapshotQueries.swift
Queries/HealthKitImport.swift
Queries/LogQueries.swift
Queries/PhotoQueries.swift
Queries/WeekQueries.swift
Migrations/M002_AddWaterOz.swift
Migrations/M003_UniqueHealthKitUuid.swift
```

**Tests** — 7 of 9 files
```
BodyMetricsSnapshotQueriesTests · HealthKitImportTests · LogQueriesTests
PhotoQueriesTests · WeekExportTests · WeekQueriesTests · WeekTests
```

**Config and docs**
```
Info.plist                       HealthKit usage strings, UIFileSharingEnabled,
                                 LSSupportsOpeningDocumentsInPlace
RecompTracker.entitlements       iCloud container (nothing left that syncs)
docs/decisions/001-cloudkit-over-supabase.md
docs/decisions/003-ckasset-for-photos.md
docs/healthkit-scope.md
docs/sync-strategy.md
docs/schema.md                   rewritten, not deleted
```

`docs/decisions/002-grdb-over-coredata.md` stays — still true, still the reason the
storage layer looks the way it does.

### Two helpers die with their files

- `epleyOneRepMax` — in `LogQueries.swift`, dies with PR detection
- `Calendar.mondayFirst` — in `Export/Week.swift`, dies with date-keying

Both were referenced from files we are keeping. Because *both call sites also go away*,
neither needs rehoming. Verify this before deleting; a stale reference will stop the
build somewhere confusing.

### Migration strategy

`AppMigrator` sets `eraseDatabaseOnSchemaChange = true` under DEBUG. No data is being
preserved, so **rewrite `M001` in place** and let GRDB rebuild. No drop migration, no
`M004`.

Assumes Debug builds installed from Xcode. Confirm before relying on it.

---

## Commit plan

| # | Commit | Shape |
|---|--------|-------|
| 1 | **Strip** | Delete the 33 files above, gut `ContentView` to a stub, clean `Info.plist` and entitlements. Tests green before anything new lands. |
| 2 | **Schema** | Rewrite `M001` to the three tables. Rewrite `Workout`, `Exercise`; replace `ExerciseSet` with `ExerciseLog`. |
| 3 | **Program** | `Program+Cycle3.swift` — 3 phases × 7 slots, cue split, mobility finisher constant. |
| 4 | **Queries** | `(phase, ordinal)` get-or-create, log upsert, `lastLog(exerciseId:)`, pending-ordinal resolution, per-phase completion count. |
| 5 | **UI** | Home (3 blocks) and session detail. |

Commit 1 is the largest diff and the least interesting, but it is where a stray
reference stops the build in a confusing place. It ships alone, green.

---

## Deferred

Pinned deliberately. Both survive here so the next session starts from this document.

### 1. Weight or reps dropping across rounds

You log round one and use that weight for all rounds. If fatigue forces a drop at round
six, that is currently unrecorded — the model has one weight and one rep count per
exercise, full stop.

Sean is thinking about what he'd actually want here. Not designed. Do not invent a
solution for it.

### 2. Cardio

Not modeled at all yet. Known shape:

- Sessions look like 3 min run / 2 min walk × 5 = 25 min, so **both modes in one session**
- Prescriptions carry speed and incline: *walk 4.0 at 7%*, *run 7.0 at 4%*
- Attaches to slots 3 and 7, **and** to afternoon sessions independent of slot
- The JSON's `cardioAddOn` field is currently ignored

Sean will bring real session examples and we design it then. Weights must be working
first.

---

## Revoked

Every previously locked-in architectural decision was cleared during this overhaul. They
described the old app. They are history, not constraints.

Explicitly dead:

- **Top sets, Epley e1RM, PR detection.** Sean does not want a 1RM estimate. He wants
  last week's number. This is why mixed-unit `reps` is safe.
- `is_top_set`, `is_warmup`, `rir` — schema columns never exposed in the UI
- Name-prefix supersets (`1a ·`) — Cycle 3 has explicit `supersetWith` fields, and
  supersets need no structural support under per-exercise logging anyway
- HealthKit body-fat range validation, sleep exclusion, Saturday HIIT session typing —
  all describe removed features
- Program-as-code-constant, async-at-DB-boundary, save-per-field-on-focus-loss — no
  longer *locked*, but carried forward because they are still right. Save-per-field
  matters more now, not less: you are mid-set with a phone in your hand.

---

## Open

The five commits above are done. The app builds, runs, and does the sentence at
the top of this document.

Still outstanding, in the order they are likely to matter:

1. **Cardio** — see [Deferred](#deferred) above. Sean brings real session
   examples; design conversation before code.
2. **Weight or reps dropping across rounds** — see [Deferred](#deferred).
   Sean's call, not designed.
3. **Session screen polish** — see `docs/backlog.md`. Cosmetic only: prev/next
   button alignment, a stray list separator, chevron order.

Nothing here blocks using the app.
