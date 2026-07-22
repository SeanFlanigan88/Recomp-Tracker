# ADR-003: CKAsset for progress photos

## Status
Accepted, 2026-07-22

## Context

Progress photos need to sync across devices. Options:

1. **CKAsset** — CloudKit's blob storage primitive
2. **Base64-encoded string field in the record** — bytes stored directly in the record
3. **External storage (S3, etc.) with URLs in the record**

## Decision

CKAsset.

## Rationale

- CKRecord fields cap at 1MB. A single progress photo can easily exceed that; CKAsset has no practical size limit.
- CKAsset is designed for exactly this: large binary data that shouldn't sync eagerly with every record fetch. Photos download on demand when displayed.
- External storage would require a second service (S3 bucket, auth, TLS) with no benefit over CloudKit's built-in solution.

## Consequences

- Photos are lazy-loaded. First view of an old photo on a new device has a small delay while it downloads.
- We maintain a local cache directory for downloaded photos. Cache eviction is a real concern at scale but not for years.
- Total storage estimate: ~600MB/year at 3 angles × 2 poses × weekly cadence × ~2MB per photo. Well inside CloudKit free tier.

## Alternatives revisited when

- We add video (progress videos) — CKAsset still works but sizes grow fast
- CloudKit storage costs become material (very unlikely for personal use)
