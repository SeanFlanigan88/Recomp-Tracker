import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Filesystem I/O for progress photos.
///
/// Photos live under `Documents/progress_photos/<uuid>.<ext>`. The DB stores
/// the path *relative* to Documents (e.g. `progress_photos/abc.heic`) because
/// iOS may relocate the app container across installs — absolute paths
/// silently break after restore.
///
/// This type is the whole filesystem story for photos. Insertion order:
/// write the file, then insert the DB row. On DB-insert failure the caller
/// asks `PhotoStore` to unlink the just-written file so nothing is orphaned.
/// If the *reverse* fails (crash between file write and DB insert), the
/// orphan sweep can reconcile via `AppDatabase.allProgressPhotoPaths()` —
/// wired up in a later commit.
public final class PhotoStore: @unchecked Sendable {

    /// Relative-to-Documents directory that holds all photo files.
    public static let relativeDirectory = "progress_photos"

    private let fileManager: FileManager
    private let documentsURL: URL
    private let photosURL: URL

    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.photosURL = documentsURL.appendingPathComponent(
            Self.relativeDirectory,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: photosURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Write

    /// Persist `data` under a fresh UUID filename with the extension inferred
    /// from the bytes. Returns the DB-storable relative path.
    ///
    /// Uses `.atomic` writes so a mid-write crash leaves no half-file — the
    /// path either exists complete or doesn't exist at all.
    public func save(data: Data) throws -> String {
        let ext = Self.fileExtension(for: data)
        let filename = "\(UUID().uuidString).\(ext)"
        let absolute = photosURL.appendingPathComponent(filename)
        try data.write(to: absolute, options: .atomic)
        return "\(Self.relativeDirectory)/\(filename)"
    }

    /// Delete the file at the given DB-relative path. Best-effort — a
    /// missing file is not an error (the row may already be gone, or an
    /// earlier crash left it in that state).
    public func delete(relativePath: String) {
        let url = absoluteURL(for: relativePath)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Read

    /// Reconstruct the absolute URL for a stored relative path. Callers
    /// must never persist this URL — it's valid only for this app-container
    /// lifetime.
    public func absoluteURL(for relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }

    // MARK: - Content-type sniffing

    /// Pick the on-disk extension by asking ImageIO what UTI the bytes are.
    /// Falls back to `"img"` when identification fails — the file is still
    /// usable via `Image(uiImage:)`, we just can't name it accurately.
    static func fileExtension(for data: Data) -> String {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let utiRaw = CGImageSourceGetType(source) as String?,
            let type = UTType(utiRaw),
            let ext = type.preferredFilenameExtension
        else {
            return "img"
        }
        return ext
    }
}

// MARK: - EXIF extraction

/// Best-effort EXIF `DateTimeOriginal` reader.
///
/// EXIF stores dates as `"yyyy:MM:dd HH:mm:ss"` with no timezone. We
/// interpret them as `TimeZone.current` — a photo shot on this device in
/// this timezone is the overwhelmingly common case. If EXIF is missing
/// (Camera app metadata disabled, screenshot, edited-and-re-saved image),
/// the caller falls back to `Date()`.
public enum EXIF {

    public static func creationDate(from data: Data) -> Date? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: raw)
    }
}
