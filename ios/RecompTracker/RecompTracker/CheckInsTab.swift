import SwiftUI
import RecompCore

/// The Check-ins tab.
///
/// For commit #7 this is deliberately minimal — the tab exists to house the
/// "Export this week" flow, nothing more. The weekly reflection form (mood,
/// adherence, energy, coach notes) is commit #8.
///
/// Flow: tab loads → shows a summary of the current Monday-Sunday week and
/// its status (partial vs completed) → tap Export → the assembler + writer
/// run → a share sheet offers the folder for AirDrop / upload / etc. On
/// success the toast confirms the file path so Sean can also find it in
/// Files > On My iPhone > Recomp Tracker > exports.
struct CheckInsTab: View {

    @Environment(\.appDatabase) private var appDatabase: AppDatabase?

    @State private var isExporting = false
    @State private var lastExportURL: URL?
    @State private var errorMessage: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Check-ins")
        }
        .keyboardDoneToolbar()
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
    }

    // MARK: - Content

    private var content: some View {
        let week = Week.containing(Date())
        return List {
            weekSummarySection(for: week)
            exportSection(for: week)
            comingSoonSection
        }
    }

    // MARK: - Sections

    private func weekSummarySection(for week: Week) -> some View {
        let cycle = Program.cycle2
        let weekNumber = cycle.weekNumber(for: week.start)
        return Section {
            LabeledContent("Week of") {
                Text(week.startDateSlug)
                    .monospacedDigit()
            }
            LabeledContent("Range") {
                Text(rangeString(for: week))
            }
            if let n = weekNumber {
                LabeledContent("Cycle") {
                    Text("\(cycle.name) · Week \(n)")
                }
            }
            LabeledContent("Status") {
                Text(week.isPartial ? "Partial (mid-week)" : "Complete")
                    .foregroundStyle(week.isPartial ? .orange : .green)
            }
        } header: {
            Text("Current week")
        } footer: {
            if week.isPartial {
                Text("A mid-week export only covers Monday through today.")
            } else {
                Text("Monday–Sunday, complete.")
            }
        }
    }

    private func exportSection(for week: Week) -> some View {
        Section {
            Button {
                Task { await runExport(for: week) }
            } label: {
                HStack {
                    if isExporting {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Text(isExporting ? "Exporting…" : "Export this week to Files")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isExporting || appDatabase == nil)

            if let url = lastExportURL {
                LabeledContent("Last export") {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button {
                    shareItem = ShareItem(url: url)
                } label: {
                    Label("Share folder", systemImage: "square.and.arrow.up")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Writes to Files > On My iPhone > Recomp Tracker > exports. Re-exporting the same week overwrites its folder.")
        }
    }

    private var comingSoonSection: some View {
        Section {
            Text("Weekly reflection form — mood, adherence, energy, coach notes — lands in a later commit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Coming later")
        }
    }

    // MARK: - Actions

    private func runExport(for week: Week) async {
        guard let db = appDatabase else { return }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let assembled = try await WeekExport.assemble(
                week: week,
                db: db
            )
            let store = try PhotoStore()
            let writer = WeekExportWriter(photoStore: store)
            let folder = try writer.write(assembled)
            lastExportURL = folder
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    private func rangeString(for week: Week) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "MMM d"
        let end = week.isPartial ? week.effectiveEnd : week.end.addingTimeInterval(-1)
        return "\(df.string(from: week.start))–\(df.string(from: end))"
    }
}

// MARK: - Share plumbing

/// Wraps a URL so `.sheet(item:)` can drive it.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController bridge. Files-app-visible folders can be
/// AirDropped, uploaded, or copied elsewhere via this sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
