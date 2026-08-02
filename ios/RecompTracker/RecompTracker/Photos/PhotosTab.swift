import SwiftUI
import RecompCore

/// The Photos tab: a scrolling grid of progress photos, newest first, with
/// a "+" that opens the import sheet.
///
/// Owns two pieces of shared state on behalf of its children:
///   - the loaded photo list, which is reloaded after every import;
///   - the gap toast, raised when an import summary reports any rows saved
///     without a body-composition snapshot.
struct PhotosTab: View {

    @Environment(\.appDatabase) private var appDatabase: AppDatabase?

    @State private var photos: [ProgressPhoto] = []
    @State private var showImportSheet = false
    @State private var selectedPhoto: ProgressPhoto?
    @State private var toast: ToastPayload?

    // Fixed 3-column grid. Scrollable. Revisit column count when weekly
    // shoots start to add up — see the "grid gets long" backlog note in
    // the retention-policy spike.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 3
    )

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Photos")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Import photos")
                    }
                }
                .navigationDestination(item: $selectedPhoto) { photo in
                    PhotoDetailView(photo: photo, onDelete: {
                        Task { await deletePhoto(photo) }
                    })
                }
        }
        .keyboardDoneToolbar()
        .sheet(isPresented: $showImportSheet) {
            PhotoImportSheet(onFinish: { summary in
                Task { await handleImportFinished(summary) }
            })
        }
        .overlay(alignment: .bottom) {
            if let toast {
                GapToast(payload: toast) {
                    self.toast = nil
                }
                .padding(.bottom, 24)
                .padding(.horizontal)
            }
        }
        .task {
            await reload()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty {
            emptyState
        } else {
            gridView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No progress photos yet")
                .font(.headline)
            Text("Tap + to import from your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    Button {
                        selectedPhoto = photo
                    } label: {
                        PhotoGridThumbnail(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private func reload() async {
        guard let db = appDatabase else { return }
        do {
            photos = try await db.progressPhotos()
        } catch {
            // Non-fatal; leave the current list in place. A real user-facing
            // error surface can come with an "Analysis" pass on the tab.
        }
    }

    private func handleImportFinished(_ summary: PhotoImportSummary) async {
        await reload()
        if summary.inserted > 0 {
            toast = ToastPayload(
                message: toastCopy(for: summary),
                tone: summary.gappedRows > 0 ? .warning : .success
            )
        }
    }

    private func deletePhoto(_ photo: ProgressPhoto) async {
        guard let db = appDatabase, let id = photo.id else { return }
        do {
            let deletedPath = try await db.deleteProgressPhoto(id: id)
            if let deletedPath {
                // Best-effort file unlink. If it fails, the orphan sweep
                // (added in a follow-up) will pick it up.
                (try? PhotoStore())?.delete(relativePath: deletedPath)
            }
            selectedPhoto = nil
            await reload()
        } catch {
            // Silent for now — deletion failure is rare and non-destructive.
        }
    }

    private func toastCopy(for summary: PhotoImportSummary) -> String {
        if summary.gappedRows == 0 {
            return "Saved \(summary.inserted) \(summary.inserted == 1 ? "photo" : "photos")."
        }
        return "Saved \(summary.inserted). \(summary.gappedRows) without body-comp snapshot (no reading within 24 hours)."
    }
}

// MARK: - Grid thumbnail

/// One square thumbnail in the grid. Loads the image lazily off-main from
/// disk into a UIImage; while loading, shows a placeholder.
///
/// Kept simple: no thumbnail cache, no downsampling. LazyVGrid virtualizes
/// off-screen rows so we're only paying for what's visible. Add a real
/// thumbnail pipeline if scrolling ever gets janky.
private struct PhotoGridThumbnail: View {

    let photo: ProgressPhoto

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            angleBadge
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
            dateBadge
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: photo.id) {
            await loadImage()
        }
    }

    private var angleBadge: some View {
        Text("\(photo.angle.shortLabel) · \(photo.pose.displayName)")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private var dateBadge: some View {
        Text(photo.date.formatted(.dateTime.month(.abbreviated).day()))
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func loadImage() async {
        // The disk read is small (single-file) and .task runs off the main
        // actor, so this is safe to do inline without a background queue.
        guard let store = try? PhotoStore() else { return }
        let url = store.absoluteURL(for: photo.photoPath)
        guard let data = try? Data(contentsOf: url) else { return }
        image = UIImage(data: data)
    }
}
