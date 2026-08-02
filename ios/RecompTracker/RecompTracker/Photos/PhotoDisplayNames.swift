import RecompCore

// Display strings for the photo enums. RecompCore stays
// presentation-agnostic; these live in the iOS target alongside the views
// that use them.

extension ProgressPhoto.Angle {
    /// Short label for compact controls (menu pickers, list tiles).
    var shortLabel: String {
        switch self {
        case .front:     return "Front"
        case .sideLeft:  return "Side · L"
        case .sideRight: return "Side · R"
        case .back:      return "Back"
        }
    }
}

extension ProgressPhoto.Pose {
    var displayName: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .flexed:  return "Flexed"
        }
    }
}

extension ProgressPhoto.CadenceTag {
    var displayName: String {
        switch self {
        case .weekly:    return "Weekly"
        case .biweekly:  return "Biweekly"
        case .monthly:   return "Monthly"
        }
    }
}
