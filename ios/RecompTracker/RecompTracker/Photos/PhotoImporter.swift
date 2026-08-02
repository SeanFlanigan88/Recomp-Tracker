import Foundation
import RecompCore

/// One row's worth of "ready to import" data. Built by the import sheet
/// as the user tags each staged photo, then handed to `PhotoImporter` in a
/// batch.
struct PhotoImportItem {
    /// Raw image bytes as loaded from `PhotosPickerItem.loadTransferable`.
    let data: Data
    /// EXIF `DateTimeOriginal` if present; caller supplies `Date()` fallback.
    let capturedAt: Date
    let angle: ProgressPhoto.Angle
    let pose: ProgressPhoto.Pose
    let notes: String?
}

/// Result of a batch import, for the save-time gap toast.
struct PhotoImportSummary {
    let inserted: Int
    /// Count of rows whose weight *and* body-fat snapshots are both nil
    /// (nearest reading was outside the 24hr window or no readings existed).
    let gappedRows: Int
}

/// Bundles the batch-level context that applies uniformly to every item.
struct PhotoImportBatch {
    let cadenceTag: ProgressPhoto.CadenceTag?
    let items: [PhotoImportItem]
}

/// Runs a batch import. Kept as a stateless enum-namespace because there's
/// no per-import state worth carrying — the orchestration is just a
/// sequence of async calls.
///
/// Insert order per item: write file → insert row. If the row insert
/// throws, the just-written file is unlinked so we don't leak. If the file
/// write throws, no DB row is touched. The batch does not run in a single
/// transaction: partial success on a batch is preferable to all-or-nothing
/// (a corrupted 3rd item shouldn't lose the 2 that succeeded).
enum PhotoImporter {

    /// The ±24hr window Sean locked in. Exported so the sheet's per-tile
    /// gap indicator uses the same constant.
    static let snapshotWindow: TimeInterval = 24 * 3600

    static func run(
        _ batch: PhotoImportBatch,
        db: AppDatabase,
        store: PhotoStore
    ) async throws -> PhotoImportSummary {
        var inserted = 0
        var gappedRows = 0

        for item in batch.items {
            // 1. Snapshot lookups within the ±24hr window. Independent per
            //    column so a sparse manual weight row can still contribute
            //    weight while the BF column stays honest-null.
            let weight = try await db.nearestWeightReading(
                to: item.capturedAt,
                within: snapshotWindow
            )
            let bodyFat = try await db.nearestBodyFatReading(
                to: item.capturedAt,
                within: snapshotWindow
            )

            // 2. Write file. Failure aborts this item; the loop continues
            //    to the next.
            let relativePath: String
            do {
                relativePath = try store.save(data: item.data)
            } catch {
                // A file write can fail on out-of-space or permission
                // issues. Log and skip; other items in the batch may still
                // succeed. Consider surfacing to the user in a follow-up
                // if this becomes common.
                continue
            }

            // 3. Insert row. On failure, unlink the file we just wrote.
            let row = ProgressPhoto(
                date: Calendar.current.startOfDay(for: item.capturedAt),
                timestamp: item.capturedAt,
                angle: item.angle,
                pose: item.pose,
                photoPath: relativePath,
                weightLbAtCapture: weight,
                bfPctAtCapture: bodyFat,
                cadenceTag: batch.cadenceTag,
                notes: (item.notes?.isEmpty ?? true) ? nil : item.notes
            )

            do {
                _ = try await db.insertProgressPhoto(row)
            } catch {
                store.delete(relativePath: relativePath)
                throw error
            }

            inserted += 1
            if weight == nil && bodyFat == nil { gappedRows += 1 }
        }

        return PhotoImportSummary(inserted: inserted, gappedRows: gappedRows)
    }
}
