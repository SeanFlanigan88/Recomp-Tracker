import SwiftUI
import UIKit

extension View {
    /// Adds a "Done" button to the keyboard accessory bar that dismisses the
    /// keyboard. Apply to any view that hosts editable fields; the toolbar
    /// only appears while the keyboard is up, so applying it to views
    /// without fields is a harmless no-op.
    ///
    /// Uses UIKit's `resignFirstResponder` so it works without a FocusState
    /// binding — one call site, no plumbing. SwiftUI's `@FocusState`
    /// bidirectionally tracks responder state, so any `.onChange(of:
    /// focusedField)` save-on-blur handlers still fire when the button is
    /// tapped.
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
