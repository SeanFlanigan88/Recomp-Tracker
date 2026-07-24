# Backlog

Deferred work with enough context that anyone (present-Sean, future-Sean, or
a fresh AI session) can pick it up without re-deriving the design.

Items are not strictly ordered by priority — they're grouped by area. Move
items to `docs/decisions/` if they grow into a real ADR.

---

## Workouts tab

### Structural superset pairing (Friday Upper)

Currently Friday's supersets are represented by name prefix (`"1a · Incline
barbell press"`, `"1b · Chest-supported DB row"`) — same as the HTML tracker.
This lets us ship without modeling pair relationships in `ProgramExercise`.

To revisit after Aug 3 with real usage data: is the prefix enough? Or is the
right shape a paired render (1a/1b side-by-side or nested) with a shared rest
timer and a "round" counter that increments once per pair?

If we go structural: add `pairId: String?` to `ProgramExercise`, group by
`pairId` at render time, and let unpaired lifts render normally.

### Warmup toggle per set

Right now every logged set is a work set (`is_warmup = false`). PR detection
already filters warmups out, so the plumbing is ready. UI: small "W" toggle
on each set row, tap to mark as warmup. Warmup sets should visually recede
(dim text) so the work sets stand out. Estimate: half a day of work.

### RIR entry per set

Schema has `rir` column (reps in reserve, 0–5 typical). Not exposed in the
UI right now. Add a third numeric column to the sets grid — "RIR" — or a
tap-to-reveal secondary row per set. Sean's brief mentioned RPE, which is
convertible (RPE = 10 − RIR); confirm whether he prefers RIR or RPE display
before adding.

### Day picker

Workouts tab shows today only. Users will want to backfill yesterday's
missed session, or preview tomorrow's plan. Add a week strip at the top:
`S M T W T F S`, today highlighted, tap to switch. When viewing a non-today
day, either allow editing (retroactive log) or preview-only (read-only plan
render). Recommend allow-editing for backfill but require an explicit
confirmation for future days.

### Full aesthetic pass (dark theme + HTML look)

The dark scheme is set via `.preferredColorScheme(.dark)` — standard iOS dark
appearance. The HTML tracker had a distinctive look: cyan/orange/green
accents, `JetBrains Mono` and `Rajdhani` fonts, subtle grid overlay, custom
card treatments. Porting that is a real design effort — a dedicated commit
after the core screens all work. Ship function first, aesthetic second.

---

## Log tab

### Daily Stoic quote above Notes

Show one quote per day, deterministic by date (same quote all day if the app
is reopened), rotating through a curated pool.

**Source data.** Bundled JSON resource in the app at
`Resources/stoic-quotes.json`. Curated set of ~200 quotes drawn from
Meditations (Aurelius), Letters and Discourses (Seneca), and Enchiridion /
Discourses (Epictetus). All public domain — no attribution licensing
concerns. Curation is a one-time task done by hand (favorites, not a scrape).

**Selection.** `index = stableHash("YYYY-MM-DD") % quotes.count`.
Deterministic, no state, no "already shown today" tracking. Rotation cycle
length equals pool size, so ~200 quotes ≈ 6 months before any repeat.

**Schema.** None. Bundled resource, no table, no migration.

**UI.** Small italic serif quote above the "Notes" section header on the
Log tab. Attribution on the following line, secondary color, smaller. No
tap-to-reroll, no favorites, no share button — this is a quiet daily prompt,
not a feature.

**Scope.** ~1 hour of code (loader, date-hash selector, view). Curation of
the quote pool is the actual work and can happen incrementally — ship with
20 quotes if that's what's ready, grow the file over time.

**Depends on.** Nothing. Ships anytime after the Log tab exists (commit #3
onward).

---

## Session row (Log tab)

Currently the Session row is display-only until a workout is logged; tapping
jumps to the Workouts tab. Once the Workouts tab has a "session detail" view,
tapping a *logged* session on the Log tab should deep-link into that detail
view rather than just the tab root.

---

## Notes field save-on-background

Log tab fields commit on focus loss. That covers tapping to another field or
tapping away to dismiss the keyboard. It does **not** cover the case of
typing in Notes and then backgrounding the app without tapping out first —
state is in-memory only until focus drops. If the app is terminated by the
OS before the user returns, that day's notes are gone.

Fix: `@Environment(\.scenePhase)` observer, save Notes (and any other
in-flight editable state) on transition to `.background` or `.inactive`.
~10 lines of code. Low urgency for a solo user, higher urgency if we ever
ship to anyone else.

---

## Sleep entry UX

First tap on the Sleep stepper from an unset state resolves to 5 as a
neutral anchor, then the tap increments/decrements from there. This means
"first tap up" lands on 6, not 5 — mildly awkward. Revisit if it grates.
Alternative: replace the always-visible stepper with a "Set sleep" button
that reveals the stepper on first tap.
