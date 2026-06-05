import SwiftUI

struct AdminShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WeeklyControlView()
            }
            .tabItem { Label("Weekly", systemImage: "calendar") }

            NavigationStack {
                IntelligenceHomeView()
            }
            .tabItem { Label("Intelligence", systemImage: "lightbulb") }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}

struct AdminPlaceholderScreen: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                Text("Prateek Weekly Control")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(title)
                    .font(MCOType.screenTitle)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(subtitle)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                SecondaryActionButton(title: actionTitle, action: action)
            }
            .padding(MCOSpace.l)
        }
    }
}
