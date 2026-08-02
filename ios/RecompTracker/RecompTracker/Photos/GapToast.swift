import SwiftUI

/// Data driving a `GapToast`. Kept as a value type so parents can hand a
/// fresh one in on each import and let identity change trigger the timer.
struct ToastPayload: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let tone: Tone

    enum Tone {
        case success
        case warning
    }
}

/// A small floating banner shown after an import completes. Auto-dismisses
/// after 15 seconds; tap-to-dismiss immediately.
///
/// The parent owns the payload — when the timer fires or the user taps,
/// this view calls `onDismiss` and the parent sets its `@State toast` to
/// nil. This keeps `GapToast` stateless aside from the timer.
struct GapToast: View {

    let payload: ToastPayload
    let onDismiss: () -> Void

    /// 15s per the design conversation. Auto-dismiss is best-effort — if
    /// the user backgrounds the app, we don't linger on return.
    private static let visibleDuration: Duration = .seconds(15)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(payload.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task(id: payload.id) {
            try? await Task.sleep(for: Self.visibleDuration)
            if !Task.isCancelled { onDismiss() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var icon: String {
        switch payload.tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "clock.badge.questionmark"
        }
    }

    private var iconColor: Color {
        switch payload.tone {
        case .success: return .green
        case .warning: return .orange
        }
    }
}
