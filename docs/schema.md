# Data Schema

Full data model for Recomp Tracker. This is the load-bearing document — the schema is what carries forward regardless of framework or UI decisions.

## Design principles

1. **Source tracking on any auto-imported data.** Every row that could come from HealthKit has a `source` field and a `healthkit_uuid` for dedup and reconciliation.
2. **Denormalize snapshots at the point of capture.** Progress photos store the weight and body fat % at the time the photo was taken, so historical comparisons don't drift if HealthKit later revises the underlying reading.
3. **Sparse rows are fine.** SQLite handles nullable columns efficiently. A morning HRV reading fills one field; a scale reading fills eight. Both live in the same `body_metrics` table.
4. **Optional fields for progressive adoption.** RIR, mood, sleep quality, etc. are optional. Log them when useful, skip when not. The schema supports both without branching.

## Tables

### `body_metrics`

All quantitative body composition, cardiovascular, and sleep data. One row per measurement event.

    id                   INTEGER PRIMARY KEY
    timestamp            DATETIME NOT NULL
    source               TEXT NOT NULL     -- 'healthkit' | 'manual'
    healthkit_uuid       TEXT              -- for dedup/reconciliation
    weight_lb            REAL
    body_fat_pct         REAL
    lean_mass_lb         REAL
    bone_mass_lb         REAL
    body_water_pct       REAL
    visceral_fat_rating  REAL
    bmr_kcal             INTEGER
    resting_hr           INTEGER
    hrv_ms               REAL
    sleep_hours          REAL
    sleep_efficiency     REAL              -- 0.0 to 1.0

### `daily_log`

Subjective daily state. One row per day. Never sourced from HealthKit.

    id                     INTEGER PRIMARY KEY
    date                   DATE NOT NULL UNIQUE
    energy_1_10            INTEGER           -- 1-10 scale
    mood                   TEXT              -- freeform tag
    sleep_quality_1_10     INTEGER           -- subjective, separate from HK sleep_hours
    stress_1_10            INTEGER
    notes                  TEXT
    training_readiness     REAL              -- computed field, updated on write

### `workouts`

One row per training session.

    id                     INTEGER PRIMARY KEY
    date                   DATE NOT NULL
    started_at             DATETIME
    ended_at               DATETIME
    session_type           TEXT              -- 'push' | 'pull' | 'legs' | 'upper' | 'lower' | 'full' | 'cardio' | 'other'
    duration_min           INTEGER
    healthkit_workout_uuid TEXT              -- link to HK workout if imported
    active_kcal            INTEGER           -- from HK if available
    avg_hr                 INTEGER           -- from HK if available
    notes                  TEXT

### `exercise_sets`

One row per set. This is the highest-volume table over time.

    id             INTEGER PRIMARY KEY
    workout_id     INTEGER NOT NULL REFERENCES workouts(id)
    exercise_id    INTEGER NOT NULL REFERENCES exercises(id)
    set_number     INTEGER NOT NULL
    weight_lb      REAL
    reps           INTEGER
    rir            INTEGER           -- reps in reserve (0-5+), optional
    is_top_set     BOOLEAN DEFAULT 0 -- flag the working/heaviest set for a lift
    is_warmup      BOOLEAN DEFAULT 0
    notes          TEXT

### `exercises`

Reference table of exercises. Seeded on first launch, extensible by user.

    id                    INTEGER PRIMARY KEY
    name                  TEXT NOT NULL UNIQUE
    category              TEXT              -- 'anchor' | 'accessory' | 'cardio'
    primary_muscle_group  TEXT              -- 'chest' | 'back' | 'quads' | etc.
    movement_pattern      TEXT              -- 'push_horizontal' | 'squat' | 'hinge' | etc.
    is_bilateral          BOOLEAN DEFAULT 1
    is_custom             BOOLEAN DEFAULT 0 -- user-added vs seeded

### `nutrition_log`

Daily nutrition totals. Food-level logging is out of scope for v1.

    id             INTEGER PRIMARY KEY
    date           DATE NOT NULL UNIQUE
    kcal           INTEGER
    protein_g      INTEGER
    carbs_g        INTEGER
    fat_g          INTEGER
    target_kcal    INTEGER
    target_protein_g INTEGER
    notes          TEXT

### `progress_photos`

Photos with pose modifiers for accurate comparison. See ADR-003 for CKAsset handling.

    id                     INTEGER PRIMARY KEY
    date                   DATE NOT NULL
    timestamp              DATETIME NOT NULL
    angle                  TEXT NOT NULL     -- 'front' | 'side_left' | 'side_right' | 'back'
    pose                   TEXT NOT NULL     -- 'relaxed' | 'flexed'
    photo_path             TEXT NOT NULL     -- local file path; CKAsset in CloudKit
    weight_lb_at_capture   REAL              -- denormalized snapshot
    bf_pct_at_capture      REAL              -- denormalized snapshot
    cadence_tag            TEXT              -- 'weekly' | 'biweekly' | 'monthly'
    notes                  TEXT

### `check_ins`

Periodic review snapshots. Weekly/biweekly/monthly.

    id                     INTEGER PRIMARY KEY
    date                   DATE NOT NULL
    period_type            TEXT NOT NULL     -- 'weekly' | 'biweekly' | 'monthly'
    period_start           DATE NOT NULL
    period_end             DATE NOT NULL
    avg_weight_lb          REAL
    avg_body_fat_pct       REAL
    avg_sleep_hours        REAL
    workouts_completed     INTEGER
    total_volume_lb        REAL              -- sum of weight × reps across all working sets
    reflection_notes       TEXT
    coach_notes            TEXT              -- for conversation with Claude / trainer

## Indices

    CREATE INDEX idx_body_metrics_timestamp ON body_metrics(timestamp);
    CREATE INDEX idx_body_metrics_hk_uuid ON body_metrics(healthkit_uuid);
    CREATE INDEX idx_workouts_date ON workouts(date);
    CREATE INDEX idx_workouts_hk_uuid ON workouts(healthkit_workout_uuid);
    CREATE INDEX idx_sets_workout_id ON exercise_sets(workout_id);
    CREATE INDEX idx_sets_exercise_id ON exercise_sets(exercise_id);
    CREATE INDEX idx_photos_date ON progress_photos(date);

## Migration strategy

GRDB migrations are versioned and forward-only. Every schema change is a new migration file numbered sequentially. See `shared/Sources/RecompCore/Migrations/`.

## What's deliberately out of scope for v1

- Per-meal food logging (daily totals only)
- Cardio zone tracking (aggregate calories/duration only)
- Mesocycle/phase metadata (add when we start Cycle 3)
- Exercise-level 1RM tracking (compute from top sets on demand)
- Multi-user support
