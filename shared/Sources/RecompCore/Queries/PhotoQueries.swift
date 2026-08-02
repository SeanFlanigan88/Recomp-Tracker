import Foundation
import GRDB

// MARK: - Query API

extension AppDatabase {

    // MARK: Progress photos — list

    /// All progress photos, newest first (by `timestamp`, tie-broken by
    /// descending `id`).
    ///
    /// `limit` and `offset` support paging in the grid view. `limit == nil`
    /// returns the full set; the grid uses `LazyVGrid` and lets SwiftUI
    /// virtualize rendering, so full-list fetches are the default until we
    /// have a real reason to page.
    public func progressPhotos(
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [ProgressPhoto] {
        try await read { db in
            var request = ProgressPhoto
                .order(Column("timestamp").desc, Column("id").desc)
            if let limit {
                request = request.limit(limit, offset: offset)
            }
            return try request.fetchAll(db)
        }
    }

    // MARK: Progress photos — insert

    /// Insert a single progress photo row. Returns the row id assigned by
    /// SQLite.
    ///
    /// The caller is responsible for having already written the image bytes
    /// to disk at `photo.photoPath` before calling. This function does not
    /// touch the filesystem — RecompCore is filesystem-agnostic by design.
    @discardableResult
    public func insertProgressPhoto(_ photo: ProgressPhoto) async throws -> Int64 {
        try await write { db in
            var toInsert = photo
            try toInsert.insert(db)
            // MutablePersistableRecord.didInsert has already set the id.
            return toInsert.id!
        }
    }

    // MARK: Progress photos — update notes

    /// Update the `notes` column on a single row. All other columns are
    /// preserved. No-op if the row doesn't exist.
    public func updateProgressPhotoNotes(id: Int64, notes: String?) async throws {
        try await write { db in
            guard var row = try ProgressPhoto.fetchOne(db, key: id) else { return }
            row.notes = notes
            try row.update(db)
        }
    }

    // MARK: Progress photos — delete

    /// Delete the row with the given id and return its `photo_path` so the
    /// caller can also unlink the file from disk. Returns nil if no row
    /// existed with that id.
    ///
    /// The DB write and the file unlink live in separate layers by design —
    /// RecompCore doesn't touch the filesystem. Callers should perform the
    /// unlink best-effort after the DB delete succeeds; a file leaked by a
    /// crash between the two is cleaned up by the orphan sweep on next
    /// launch (see the iOS `PhotoStore`).
    @discardableResult
    public func deleteProgressPhoto(id: Int64) async throws -> String? {
        try await write { db in
            guard let row = try ProgressPhoto.fetchOne(db, key: id) else { return nil }
            try row.delete(db)
            return row.photoPath
        }
    }

    // MARK: Progress photos — orphan reconciliation

    /// Return every `photo_path` currently referenced by the table. Used by
    /// the iOS layer's orphan sweep on launch: any file under the photos
    /// directory that isn't in this set can be deleted.
    public func allProgressPhotoPaths() async throws -> Set<String> {
        try await read { db in
            let rows = try String.fetchAll(db, sql: """
                SELECT photo_path FROM progress_photos
                """)
            return Set(rows)
        }
    }
}
