import SwiftUI

struct CreatorShellView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: CreatorTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                    .navigationDestination(for: CreatorRoute.self) { route in
                        switch route {
                        case .shootFolio(let editing):
                            ShootFolioView(startsInEditingMode: editing)
                        case .plan(let selectedDate):
                            PlanHubView(
                                showsModeSwitch: false,
                                initialSelectedDate: selectedDate
                            )
                        }
                    }
            }
            .tabItem { Label(CreatorTab.today.rawValue, systemImage: CreatorTab.today.systemImage) }
            .tag(CreatorTab.today)
            .accessibilityIdentifier("shell.tab.today")

            NavigationStack {
                PlanHubView(showsModeSwitch: false)
            }
            .tabItem { Label(CreatorTab.plan.rawValue, systemImage: CreatorTab.plan.systemImage) }
            .tag(CreatorTab.plan)
            .accessibilityIdentifier("shell.tab.plan")

            NavigationStack {
                YouView()
            }
            .tabItem { Label(CreatorTab.you.rawValue, systemImage: CreatorTab.you.systemImage) }
            .tag(CreatorTab.you)
            .accessibilityIdentifier("shell.tab.you")
        }
        .background(PocketSheetTheme.Color.paper)
        .onChange(of: appState.pendingCreatorTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            appState.pendingCreatorTab = nil
        }
    }
}
