import SwiftUI

struct MamtaShellView: View {
    @State private var selectedTab: MamtaTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                    .navigationDestination(for: MamtaRoute.self) { route in
                        switch route {
                        case .shootFolio:
                            ShootFolioView()
                        }
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.min") }
            .tag(MamtaTab.today)

            NavigationStack {
                ShootFolioView()
            }
            .tabItem { Label("Shoot Folio", systemImage: "bookmark") }
            .tag(MamtaTab.shootFolio)

            NavigationStack {
                ArchiveView()
            }
            .tabItem { Label("Archive", systemImage: "archivebox") }
            .tag(MamtaTab.archive)

            NavigationStack {
                ProfileModeView()
            }
            .tabItem { Label("Profile", systemImage: "person.circle") }
            .tag(MamtaTab.profile)
        }
        .background(MCOTheme.Color.paper)
    }
}

struct ProfileModeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                Text("Profile")
                    .font(MCOType.screenTitle)
                Text("Mamta mode is the daily product. Prateek controls stay tucked away.")
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                SecondaryActionButton(title: "Switch to Prateek Control") {
                    appState.activeMode = .admin
                }
            }
            .padding(MCOSpace.l)
        }
    }
}
