# Sync Strategy

CloudKit-based cross-device sync between iOS and macOS. Data lives in the user's private iCloud database. Apple cannot read it; Anthropic (or any third party) has no access.

## Architecture

    Device A (iPhone)                          Device B (Mac)
    ┌──────────────────┐                       ┌──────────────────┐
    │ SwiftUI          │                       │ SwiftUI          │
    │      ↕           │                       │      ↕           │
    │ RecompCore       │                       │ RecompCore       │
    │ (models, logic)  │                       │ (models, logic)  │
    │      ↕           │                       │      ↕           │
    │ GRDB (SQLite)    │                       │ GRDB (SQLite)    │
    │      ↕           │                       │      ↕           │
    │ CloudKit sync    │◄─────────────────────►│ CloudKit sync    │
    │ layer            │       iCloud          │ layer            │
    └──────────────────┘                       └──────────────────┘

## CloudKit container

- **Identifier:** `iCloud.com.seanflanigan.recomptracker`
- **Environment:** Development for initial builds; Production before first real use
- **Database:** Private only. No public or shared databases in v1.

## Record types

Each SQLite table has a corresponding CKRecord type. Field types map directly with these exceptions:

- SQLite `INTEGER` PK → CKRecord `recordName` (String UUID)
- SQLite `DATETIME` → CKRecord `Date`
- SQLite `BOOLEAN` → CKRecord `Int64` (0/1)
- SQLite blob-like fields (photos) → CKRecord `CKAsset`

## Sync algorithm

Push (local → CloudKit) on change:
1. Local write to GRDB completes successfully
2. Enqueue CKModifyRecordsOperation with the changed record
3. On success, mark local row as synced with server change tag
4. On failure, retry with exponential backoff

Pull (CloudKit → local) on notification or app foreground:
1. Fetch changes since last known server change token
2. Apply changes in transaction to GRDB
3. Store new server change token

Conflict resolution: last-write-wins based on server timestamp. Manual entries always win over HealthKit re-imports for the same `healthkit_uuid`.

## Photos: CKAsset handling

Progress photos are stored as CKAsset. Each `progress_photos` row has a `photo_path` pointing to a local cache file. On sync:

- **Upload:** photo is copied into the app's documents directory, then referenced via CKAsset in the record
- **Download:** photo is fetched lazily on demand (when the photo is displayed), cached locally, path stored in `photo_path`
- **Storage estimate:** ~2MB per photo × 3 angles × 2 poses × 52 weeks = ~600MB/year. Well inside CloudKit free tier.

## Failure modes to design for

- User signed out of iCloud → app functions in local-only mode, warns user
- iCloud storage full → sync fails silently in background, surfaced in Settings
- Network offline → all writes queue locally, sync when connection returns
- Conflicting simultaneous edits from two devices → last-write-wins by server timestamp
