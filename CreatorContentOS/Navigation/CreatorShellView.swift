import SwiftUI

struct CreatorShellView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: CreatorTab = .today
    @State private var todayPath = NavigationPath()
    @State private var planPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $todayPath) {
                TodayView()
                    .pieceDestinations()
                    .navigationDestination(for: CreatorRoute.self) { route in
                        switch route {
                        case .shootFolio(let editing):
                            ShootFolioView(startsInEditingMode: editing)
                        case .todayShootSession:
                            TodayShootSessionView()
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

            NavigationStack(path: $planPath) {
                PlanHubView(showsModeSwitch: false, showsBackButton: false)
                    .pieceDestinations()
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
        .pocketSheetTabBarChrome()
        .pocketSheetChromePalette()
        .background(PocketSheetTheme.Color.paper)
        .onAppear {
            applyPendingCreatorTabIfNeeded()
        }
        .onChange(of: appState.pendingCreatorTab) { _, _ in
            applyPendingCreatorTabIfNeeded()
        }
        .onChange(of: appState.todayNavigationResetToken) { _, _ in
            todayPath = NavigationPath()
            planPath = NavigationPath()
        }
    }

    private func applyPendingCreatorTabIfNeeded() {
        guard let tab = appState.pendingCreatorTab else { return }
        selectedTab = tab
        appState.pendingCreatorTab = nil
    }
}
