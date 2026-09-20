# Program exercise aliases

`exercises.name` is UNIQUE and is the join key behind "what did I lift last
time". Two names means two histories, so the same movement has to resolve to the
same string in every phase it appears.

The program JSON does not do this. It packs coaching cues into names and writes
the same movement different ways in different phases. This file records what is
done about that, because the rules are not recoverable from the generated Swift.

## Rule 1 — split the cue

A trailing parenthetical is a cue, not part of the name.

    "DB row (bench-supported)"                   -> DB row          / bench-supported
    "KB goblet squat (max KB, pause at bottom)"  -> KB goblet squat / max KB, pause at bottom

Before this, 69 distinct name strings. After, 54 exercises.

## Rule 2 — strip grouping prefixes that are not the movement

`Ab circuit: ` is a heading over three ordinary exercises with normal 30-second
rests. It is stripped.

`KB complex: ` is **kept**. A complex swing is 6 reps at zero rest inside a
chain; a standalone `KB swing` is a 15-rep set. They are different enough that
merging them would make "last time" misleading rather than helpful.

## Rule 3 — alias the naming drift

| Written as | Resolves to | Why |
|---|---|---|
| `KB complex: goblet squat` (P1) | `KB complex: squat` | same movement in the same complex |
| `KB complex: reverse lunge` (P1) | `KB complex: lunge` | same |
| `Bench dip` (P2) | `Dip` + cue `bench` | P3 writes it `Dip (bench)` |
| `Ab circuit: plank` (P3) | `Plank` | same 3×45 sec as P2's weighted plank |
| `Single-leg step-up` (P3) | `Step-up` + cue `single-leg` | Sean's call — same movement |
| `Calf raise` (P1 Mon) | `Standing calf raise` | Sean's call — same movement |

The last two are training judgments, not text rules. They were confirmed rather
than inferred, and should be re-confirmed if a future cycle reuses the names.

## Rule 4 — split combined entries

Phase 3 Friday prescribes `DB curl / Hammer curl (alternate weekly)` — one entry
covering two movements. As a single combined name it would inherit nothing from
the `DB curl` and `Hammer curl` logged in Phases 1 and 2.

It becomes two rows. Fill in whichever you did that week; leave the other blank.

## Result

47 canonical exercises, 29 of which appear in two or more phases. Both numbers
are asserted in `Cycle3Tests` — if a regeneration changes them, that is a signal
to come back here, not to update the assertion.

## Dropped from the JSON

Not represented anywhere, and only recoverable by regenerating:

- `restSeconds` / `restAfterPairSeconds` — no rest timer is planned
- `supersetWith` — supersets need no structure when logging is per-exercise;
  paired movements simply sit adjacent in the list
- `note` — folded into `cue`, since two display fields would be one too many
