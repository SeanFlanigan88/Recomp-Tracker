import SwiftUI
import PhotosUI
import RecompCore

/// The import flow for progress photos.
///
/// Presented as a sheet from `PhotosTab`. Two phases in one view:
///   1. `PhotosPicker` for multi-select from the library.
///   2. Once photos load, a scrolling list of tagging tiles — thumbnail on
///      the left, angle + pose pickers on the right, notes disclosure,
///      per-tile gap indicator.
///
/// Save fires `PhotoImporter.run(...)`, which writes files, inserts rows,
/// and returns a summary. The summary drives a save-time gap toast owned
/// by `PhotosTab`.
///
/// "No orphans" contract: every row inserted has angle *and* pose set. The
/// Save button is disabled until every staged photo has both. To exclude a
/// photo from the batch, remove it via its tile's X — un-tagging is not a
/// path to skip.
struct PhotoImportSheet: View {

    @Environment(\.appDatabase) private var appDatabase: AppDatabase?
    @Environment(\.dismiss) private var dismiss

    /// Called by the tab after save, with the import summary so the tab
    /// can raise a gap toast and reload its grid.
    let onFinish: (PhotoImportSummary) -> Void

    // MARK: - State

    /// PhotosPicker binding. Populated by the picker sheet on selection.
    @State private var pickerItems: [PhotosPickerItem] = []

    /// One entry per successfully loaded photo. Rebuilt when `pickerItems`
    /// changes.
    @State private var staged: [StagedPhoto] = []

    /// Cadence applies to the whole batch.
    @State private var cadence: ProgressPhoto.CadenceTag = .weekly

    /// Async progress states.
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadError: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
                .onChange(of: pickerItems) { _, newItems in
                    Task { await loadStaged(from: newItems) }
                }
        }
        .keyboardDoneToolbar()
    }

    @ViewBuilder
    private var content: some View {
        if staged.isEmpty && !isLoading {
            emptyPickerState
        } else if isLoading {
            ProgressView("Loading photos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            taggingList
        }
    }

    // MARK: - Empty state (before pick)

    private var emptyPickerState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Pick the photos from this session")
                .font(.headline)
            Text("Tag angle and pose per shot after selecting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PhotosPicker(
                selection: $pickerItems,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose photos", systemImage: "photo.stack")
            }
            .buttonStyle(.borderedProminent)
            if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tagging list

    private var taggingList: some View {
        List {
            Section {
                Picker("Cadence", selection: $cadence) {
                    ForEach(ProgressPhoto.CadenceTag.allCases, id: \.self) { tag in
                        Text(tag.displayName).tag(tag)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to every photo in this batch.")
            }

            Section {
                ForEach($staged) { $item in
                    PhotoTaggingRow(item: $item) {
                        staged.removeAll { $0.id == item.id }
                    }
                }
            } footer: {
                Text("Save is enabled when every photo has both an angle and a pose.")
            }
        }
    }

    // MARK: - Loading

    private func loadStaged(from items: [PhotosPickerItem]) async {
        guard let db = appDatabase else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        var out: [StagedPhoto] = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                let capturedAt = EXIF.creationDate(from: data) ?? Date()

                // Per-tile gap indicator uses the same ±24hr window as the
                // importer — same call site, same source of truth.
                let weight = try await db.nearestWeightReading(
                    to: capturedAt,
                    within: PhotoImporter.snapshotWindow
                )
                let bodyFat = try await db.nearestBodyFatReading(
                    to: capturedAt,
                    within: PhotoImporter.snapshotWindow
                )

                out.append(
                    StagedPhoto(
                        data: data,
                        capturedAt: capturedAt,
                        nearestWeight: weight,
                        nearestBodyFat: bodyFat
                    )
                )
            } catch {
                loadError = "Couldn't load one of the selected photos: \(error.localizedDescription)"
            }
        }
        staged = out
    }

    // MARK: - Save

    private var canSave: Bool {
        !staged.isEmpty
            && !isSaving
            && staged.allSatisfy { $0.angle != nil && $0.pose != nil }
    }

    private func save() async {
        guard let db = appDatabase else { return }
        isSaving = true
        defer { isSaving = false }

        let batch = PhotoImportBatch(
            cadenceTag: cadence,
            items: staged.compactMap { staged -> PhotoImportItem? in
                guard let angle = staged.angle, let pose = staged.pose else {
                    return nil
                }
                return PhotoImportItem(
                    data: staged.data,
                    capturedAt: staged.capturedAt,
                    angle: angle,
                    pose: pose,
                    notes: staged.notes.isEmpty ? nil : staged.notes
                )
            }
        )

        do {
            let store = try PhotoStore()
            let summary = try await PhotoImporter.run(batch, db: db, store: store)
            onFinish(summary)
            dismiss()
        } catch {
            loadError = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - StagedPhoto

/// Mutable per-photo model driving the tagging list. Angle and pose are
/// optional so the UI can enforce "must be set before save" without a
/// bogus default.
private struct StagedPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let capturedAt: Date
    var nearestWeight: Double?
    var nearestBodyFat: Double?
    var angle: ProgressPhoto.Angle?
    var pose: ProgressPhoto.Pose?
    var notes: String = ""

    /// True when we have neither a weight nor a body-fat reading within
    /// the ±24hr window — the "row will save without a snapshot" case.
    var hasGap: Bool { nearestWeight == nil && nearestBodyFat == nil }
}

// MARK: - PhotoTaggingRow

/// One tile in the tagging list. Kept as a private subview so the outer
/// `List` stays readable and SwiftUI's diffing can track rows by id.
private struct PhotoTaggingRow: View {

    @Binding var item: StagedPhoto
    let onRemove: () -> Void

    @State private var showNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    anglePicker
                    posePicker
                }
                Spacer(minLength: 0)
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from batch")
            }

            if item.hasGap {
                gapIndicator
            }

            DisclosureGroup(isExpanded: $showNotes) {
                TextField("Optional notes", text: $item.notes, axis: .vertical)
                    .lineLimit(1...3)
            } label: {
                Text("Notes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let uiImage = UIImage(data: item.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var anglePicker: some View {
        Picker("Angle", selection: $item.angle) {
            Text("Angle").tag(Optional<ProgressPhoto.Angle>.none)
            ForEach(ProgressPhoto.Angle.allCases, id: \.self) { angle in
                Text(angle.shortLabel).tag(Optional(angle))
            }
        }
        .pickerStyle(.menu)
    }

    private var posePicker: some View {
        Picker("Pose", selection: $item.pose) {
            Text("Pose").tag(Optional<ProgressPhoto.Pose>.none)
            ForEach(ProgressPhoto.Pose.allCases, id: \.self) { pose in
                Text(pose.displayName).tag(Optional(pose))
            }
        }
        .pickerStyle(.menu)
    }

    private var gapIndicator: some View {
        Label("No weight/body-fat reading within 24 hours",
              systemImage: "clock.badge.questionmark")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
