# ADR-001: CloudKit over Supabase for sync

## Status
Accepted, 2026-07-22

## Context

Cross-device sync between iOS and macOS is required. Data lives on the user's devices; the user is the sole reader/writer. Options considered:

1. **CloudKit** — Apple's native sync, iCloud-backed
2. **Supabase self-hosted** — Postgres + realtime, on a VPS
3. **File-based sync via iCloud Drive / Dropbox** — SQLite file synced as a document

## Decision

CloudKit.

## Rationale

- Both target devices are Apple platforms. CloudKit has zero infrastructure cost, zero maintenance overhead, and end-to-end encryption by default.
- The user cannot access their own data outside of the app, which is acceptable — the app is the only intended access surface.
- Supabase would be strictly more work (VPS, backups, TLS, auth) for identical functionality in this use case.
- File-based sync has concurrency problems that are unacceptable for a write-heavy log.

## Consequences

- Locked to Apple ecosystem. Android or web support would require a rewrite of the sync layer.
- Debugging sync issues requires familiarity with CloudKit's mental model (change tokens, zones, subscriptions).
- If we ever want programmatic access to the data outside the app (e.g., a Python analysis script), we need to either export via the app or add a secondary sync path. Acceptable tradeoff.

## Alternatives revisited when

- We want to share data with a non-Apple user
- We want server-side computation or scheduled jobs on the data
- Data volume exceeds CloudKit free tier limits (~1TB per user)
