import SwiftUI
import RecompCore

/// Full-screen detail view for a single progress photo.
///
/// Shows the image, snapshot metadata (weight, body fat, timestamp, angle,
/// pose, notes), and a delete affordance in the toolbar. No swipe-between-
/// photos or notes editing in this MVP — both are on the backlog.
struct PhotoDetailView: View {

    let photo: ProgressPhoto
    /// Fired when the user confirms delete. The tab handles the DB + file
    /// side of the delete and dismisses this view via its `selectedPhoto`
    /// binding.
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageArea
                metadataBlock
                if let notes = photo.notes, !notes.isEmpty {
                    notesBlock(notes)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete photo")
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The image file and the recorded snapshot will be removed. This can't be undone.")
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageArea: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.4))
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    ProgressView()
                }
        }
    }

    // MARK: - Metadata

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Chip(text: photo.angle.shortLabel)
                Chip(text: photo.pose.displayName)
                if let cadence = photo.cadenceTag {
                    Chip(text: cadence.displayName)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Weight").foregroundStyle(.secondary)
                    Text(weightText).monospacedDigit()
                }
                GridRow {
                    Text("Body fat").foregroundStyle(.secondary)
                    Text(bodyFatText).monospacedDigit()
                }
                GridRow {
                    Text("Captured").foregroundStyle(.secondary)
                    Text(photo.timestamp.formatted(date: .long, time: .shortened))
                }
            }
            .font(.subheadline)
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.body)
        }
    }

    private var weightText: String {
        if let w = photo.weightLbAtCapture {
            return String(format: "%.1f lb", w)
        }
        return "—"
    }

    private var bodyFatText: String {
        if let bf = photo.bfPctAtCapture {
            return String(format: "%.1f%%", bf)
        }
        return "—"
    }

    // MARK: - Loading

    private func loadImage() async {
        guard let store = try? PhotoStore() else { return }
        let url = store.absoluteURL(for: photo.photoPath)
        guard let data = try? Data(contentsOf: url) else { return }
        image = UIImage(data: data)
    }
}

// MARK: - Chip

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.2))
            .clipShape(Capsule())
    }
}
