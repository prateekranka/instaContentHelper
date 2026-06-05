import SwiftUI

struct NotTodaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            VStack(spacing: MCOSpace.l) {
                VStack(spacing: MCOSpace.s) {
                    Text("Not today")
                        .font(MCOType.screenTitle)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Rectangle()
                        .fill(MCOTheme.Color.brass)
                        .frame(width: 32, height: 1)
                    Text("Choose the smallest useful win.")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                .padding(.top, MCOSpace.l)

                VStack(spacing: MCOSpace.m) {
                    BackupOptionRow(symbol: "10.circle", title: "10-second story", subtitle: "Keep the streak alive.")
                    BackupOptionRow(symbol: "feather", title: "Caption-only post", subtitle: "Share the thought.")
                    BackupOptionRow(symbol: "bookmark", title: "Save for tomorrow", subtitle: "Keep the card ready.")
                }

                Spacer()

                GlassCommandBar {
                    PrimaryActionButton(title: "Use backup") {
                        services.completeToday(with: .usedBackup)
                        dismiss()
                    }
                }
            }
            .padding(MCOSpace.l)
            .padding(.top, MCOSpace.l)
            .padding(.bottom, MCOSpace.l)
        }
    }
}

struct BackupOptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        JournalBlock {
            HStack(spacing: MCOSpace.m) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(title)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(subtitle)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }
}

#Preview {
    NotTodaySheet()
        .environment(AppServices.preview)
        .environment(AppState())
}
