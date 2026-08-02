import XCTest
import GRDB
@testable import RecompCore

/// Coverage for CRUD on `progress_photos`. Filesystem I/O is intentionally
/// out of scope for RecompCore — these tests exercise the DB layer only.
final class PhotoQueriesTests: XCTestCase {

    // MARK: - Fixtures

    private func makePhoto(
        timestamp: Date,
        angle: ProgressPhoto.Angle = .front,
        pose: ProgressPhoto.Pose = .relaxed,
        photoPath: String = "progress_photos/test.heic",
        weightLbAtCapture: Double? = nil,
        bfPctAtCapture: Double? = nil,
        cadenceTag: ProgressPhoto.CadenceTag? = .weekly,
        notes: String? = nil
    ) -> ProgressPhoto {
        ProgressPhoto(
            date: Calendar.current.startOfDay(for: timestamp),
            timestamp: timestamp,
            angle: angle,
            pose: pose,
            photoPath: photoPath,
            weightLbAtCapture: weightLbAtCapture,
            bfPctAtCapture: bfPctAtCapture,
            cadenceTag: cadenceTag,
            notes: notes
        )
    }

    // MARK: - Insert + list

    func testInsertProgressPhotoAssignsIdAndRoundTrips() async throws {
        let db = try AppDatabase.inMemory()
        let ts = Date()

        let id = try await db.insertProgressPhoto(
            makePhoto(
                timestamp: ts,
                photoPath: "progress_photos/abc.heic",
                weightLbAtCapture: 181.4,
                bfPctAtCapture: 18.2,
                notes: "post-shower"
            )
        )

        XCTAssertGreaterThan(id, 0)

        let all = try await db.progressPhotos()
        XCTAssertEqual(all.count, 1)
        let loaded = all[0]
        XCTAssertEqual(loaded.id, id)
        XCTAssertEqual(loaded.photoPath, "progress_photos/abc.heic")
        XCTAssertEqual(loaded.weightLbAtCapture, 181.4)
        XCTAssertEqual(loaded.bfPctAtCapture, 18.2)
        XCTAssertEqual(loaded.notes, "post-shower")
        XCTAssertEqual(loaded.cadenceTag, .weekly)
    }

    func testProgressPhotosOrderedNewestFirst() async throws {
        let db = try AppDatabase.inMemory()
        let base = Date(timeIntervalSince1970: 1_720_000_000)

        // Insert out of chronological order.
        _ = try await db.insertProgressPhoto(makePhoto(
            timestamp: base,
            photoPath: "progress_photos/oldest.heic"
        ))
        _ = try await db.insertProgressPhoto(makePhoto(
            timestamp: base.addingTimeInterval(7 * 86_400),
            photoPath: "progress_photos/newest.heic"
        ))
        _ = try await db.insertProgressPhoto(makePhoto(
            timestamp: base.addingTimeInterval(3 * 86_400),
            photoPath: "progress_photos/middle.heic"
        ))

        let all = try await db.progressPhotos()
        XCTAssertEqual(
            all.map(\.photoPath),
            ["progress_photos/newest.heic",
             "progress_photos/middle.heic",
             "progress_photos/oldest.heic"]
        )
    }

    func testProgressPhotosLimitAndOffset() async throws {
        let db = try AppDatabase.inMemory()
        let base = Date(timeIntervalSince1970: 1_720_000_000)

        for i in 0..<5 {
            _ = try await db.insertProgressPhoto(makePhoto(
                timestamp: base.addingTimeInterval(Double(i) * 86_400),
                photoPath: "progress_photos/\(i).heic"
            ))
        }

        // Newest first: 4, 3, 2, 1, 0. Page 2 with limit 2 → [2, 1].
        let page = try await db.progressPhotos(limit: 2, offset: 2)
        XCTAssertEqual(page.map(\.photoPath),
                       ["progress_photos/2.heic", "progress_photos/1.heic"])
    }

    // MARK: - Update notes

    func testUpdateNotesPreservesOtherColumns() async throws {
        let db = try AppDatabase.inMemory()
        let id = try await db.insertProgressPhoto(makePhoto(
            timestamp: Date(),
            photoPath: "progress_photos/a.heic",
            weightLbAtCapture: 180.0,
            notes: "original"
        ))

        try await db.updateProgressPhotoNotes(id: id, notes: "revised")

        let loaded = try await db.progressPhotos().first
        XCTAssertEqual(loaded?.notes, "revised")
        XCTAssertEqual(loaded?.weightLbAtCapture, 180.0,
                       "unrelated columns must be preserved")
    }

    func testUpdateNotesToNilClearsField() async throws {
        let db = try AppDatabase.inMemory()
        let id = try await db.insertProgressPhoto(makePhoto(
            timestamp: Date(),
            notes: "something"
        ))

        try await db.updateProgressPhotoNotes(id: id, notes: nil)

        let loaded = try await db.progressPhotos().first
        XCTAssertNil(loaded?.notes)
    }

    func testUpdateNotesOnMissingIdIsNoOp() async throws {
        let db = try AppDatabase.inMemory()
        // No throw expected; missing id is silently ignored.
        try await db.updateProgressPhotoNotes(id: 9_999, notes: "ignored")
    }

    // MARK: - Delete

    func testDeleteRemovesRowAndReturnsPhotoPath() async throws {
        let db = try AppDatabase.inMemory()
        let id = try await db.insertProgressPhoto(makePhoto(
            timestamp: Date(),
            photoPath: "progress_photos/to-delete.heic"
        ))

        let returnedPath = try await db.deleteProgressPhoto(id: id)
        XCTAssertEqual(returnedPath, "progress_photos/to-delete.heic",
                       "delete must return the path so the caller can unlink the file")

        let remaining = try await db.progressPhotos()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteMissingIdReturnsNil() async throws {
        let db = try AppDatabase.inMemory()
        let path = try await db.deleteProgressPhoto(id: 12_345)
        XCTAssertNil(path)
    }

    // MARK: - Orphan reconciliation

    func testAllProgressPhotoPathsReturnsCompleteSet() async throws {
        let db = try AppDatabase.inMemory()
        _ = try await db.insertProgressPhoto(makePhoto(
            timestamp: Date(),
            photoPath: "progress_photos/a.heic"
        ))
        _ = try await db.insertProgressPhoto(makePhoto(
            timestamp: Date().addingTimeInterval(-3600),
            photoPath: "progress_photos/b.heic"
        ))

        let paths = try await db.allProgressPhotoPaths()
        XCTAssertEqual(paths,
                       ["progress_photos/a.heic", "progress_photos/b.heic"])
    }

    func testAllProgressPhotoPathsEmptyWhenTableEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let paths = try await db.allProgressPhotoPaths()
        XCTAssertTrue(paths.isEmpty)
    }
}
