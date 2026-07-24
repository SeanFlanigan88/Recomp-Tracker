# Backlog

Deferred work with enough context that anyone (present-Sean, future-Sean, or
a fresh AI session) can pick it up without re-deriving the design.

Items are not strictly ordered by priority — they're grouped by area. Move
items to `docs/decisions/` if they grow into a real ADR.

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
