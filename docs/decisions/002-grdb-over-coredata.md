# ADR-002: GRDB over Core Data

## Status
Accepted, 2026-07-22

## Context

Local persistence layer needed. Options:

1. **GRDB** — Swift SQLite wrapper, type-safe, hand-written migrations
2. **Core Data** — Apple's ORM, with `NSPersistentCloudKitContainer` for automatic CloudKit sync
3. **SwiftData** — Newer Apple ORM, CloudKit sync built-in

## Decision

GRDB with a hand-written CloudKit sync layer.

## Rationale

- Real SQL. Complex queries (correlations across body_metrics and workouts, aggregate volume calculations) are trivial in SQL, painful in Core Data's predicate DSL.
- Explicit, versioned migrations. Core Data lightweight migration is fine until it isn't, and heavyweight migration is miserable.
- Testable. GRDB models are plain structs; you can unit-test business logic without a Core Data stack.
- The CloudKit sync layer becomes visible code we can debug rather than a black box that occasionally breaks in ways only Apple engineers can diagnose.

## Consequences

- We write the CloudKit sync layer ourselves. This is real work — probably 500–1000 lines of Swift with tests — but the code is legible and debuggable.
- SwiftData is off the table for v1. It's still maturing and its CloudKit integration has the same leaky-abstraction problems as Core Data's.
- If we later want to add server-side code that reads the SQLite file directly (e.g., a script that generates check-in reports), that's straightforward with GRDB and impossible with Core Data.

## Alternatives revisited when

- Apple significantly overhauls SwiftData's CloudKit integration
- The sync layer proves harder to maintain than expected
