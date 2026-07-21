import SwiftUI

/// DEBUG Admin Daily tab host wrapping `PlanHubView`. Creator Plan uses `PlanHubView` directly.
struct DayGenerationView: View {
    /// Admin chrome “Creator mode” control — only meaningful under DEBUG AdminShellView.
    var showsModeSwitch: Bool = true

    var body: some View {
        PlanHubView(showsModeSwitch: showsModeSwitch)
    }
}
