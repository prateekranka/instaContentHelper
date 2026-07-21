import SwiftUI

/// Admin Daily tab host until ticket 07 retires AdminShell. Creator Plan uses `PlanHubView` directly.
struct DayGenerationView: View {
    /// When false (Plan from Creator Profile), hide Admin-mode switch chrome.
    var showsModeSwitch: Bool = true

    var body: some View {
        PlanHubView(showsModeSwitch: showsModeSwitch)
    }
}
