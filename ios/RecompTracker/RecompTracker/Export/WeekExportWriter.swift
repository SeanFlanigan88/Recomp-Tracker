import Foundation
import RecompCore

/// Writes an `AssembledWeek` to disk as a folder under
/// `Documents/exports/`.
///
/// The folder is named `Recomp Week YYYY-MM-DD` (Monday date), so re-exports
/// of the same week collide by design — the writer deletes the existing
/// folder first, then recreates it. Different weeks produce different
/// folders and never conflict.
///
/// Contents on disk:
///   Recomp Week 2026-08-03/
///     ├── week.json                                     ← Codable payload
///     └── photos/
///         ├── 2026-08-03_08-15-42_front_relaxed.heic
///         └── ...
///
/// JSON is pretty-printed with ISO-8601 dates and snake_case keys so the
/// agent can eyeball it and diff week-to-week.
final class WeekExportWriter: @unchecked Sendable {

    /// Photo source resolver. Wired to the same `PhotoStore` the app uses
    /// for imports; injected so this type stays testable in principle.
    private let photoStore: PhotoStore
    private let fileManager: FileManager

    init(photoStore: PhotoStore, fileManager: FileManager = .default) {
        self.photoStore = photoStore
        self.fileManager = fileManager
    }

    // MARK: - Write

    /// Materialize `assembled` on disk and return the folder URL. Any
    /// existing folder for the same week is removed before writing.
    /// Individual photo copy failures are tolerated (the JSON still names
    /// them; the file just won't be present); a serialization or directory
    /// failure throws.
    @discardableResult
    func write(_ assembled: AssembledWeek) throws -> URL {
        let root = try Self.exportsDirectory(fileManager: fileManager)
        let folderName = "Recomp Week \(Self.folderDateSlug(assembled.export.week.startDate))"
        let folder = root.appendingPathComponent(folderName, isDirectory: true)

        // 1. Wipe any prior version of this week's folder.
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }

        // 2. Fresh folder + photos subfolder.
        let photosDir = folder.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

        // 3. Serialize week.json.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(assembled.export)
        try json.write(to: folder.appendingPathComponent("week.json"), options: .atomic)

        // 4. Copy each photo. Best-effort per file — a missing source
        // (e.g. a photo whose file was manually deleted from the store)
        // shouldn't tank the whole export.
        for plan in assembled.photoCopyPlan {
            let source = photoStore.absoluteURL(for: plan.sourceRelativePath)
            let dest = photosDir.appendingPathComponent(plan.destinationFileName)
            do {
                try fileManager.copyItem(at: source, to: dest)
            } catch {
                // Swallow — JSON already records the intended filename.
                continue
            }
        }

        return folder
    }

    // MARK: - Discovery

    /// The `Documents/exports/` directory, created on demand. Callers can
    /// also point the Files-app share sheet here to browse past exports.
    static func exportsDirectory(fileManager: FileManager = .default) throws -> URL {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let exports = documents.appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: exports, withIntermediateDirectories: true)
        return exports
    }

    // MARK: - Private

    private static func folderDateSlug(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
