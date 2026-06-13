import SwiftUI

struct NotTodaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            VStack(spacing: MCOSpace.l) {
                VStack(spacing: MCOSpace.s) {
                    Text("Other ideas")
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
                    BackupOptionRow(
                        symbol: "10.circle",
                        title: "10-second story",
                        subtitle: "Keep the streak alive."
                    ) {
                        complete(.backupStory)
                    }
                    BackupOptionRow(
                        symbol: "feather",
                        title: "Caption-only post",
                        subtitle: "Share the thought."
                    ) {
                        complete(.captionOnly)
                    }
                    BackupOptionRow(
                        symbol: "bookmark",
                        title: "Save for tomorrow",
                        subtitle: "Keep the card ready."
                    ) {
                        complete(.savedForTomorrow)
                    }
                }

                Spacer()

                GlassCommandBar {
                    SecondaryActionButton(title: "Skip intentionally") {
                        complete(.skippedIntentionally)
                    }
                }
            }
            .padding(MCOSpace.l)
            .padding(.top, MCOSpace.l)
            .padding(.bottom, MCOSpace.l)
        }
    }

    private func complete(_ decision: DailyDecision) {
        services.completeToday(with: decision)
        dismiss()
    }
}

struct BackupOptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }
}

#Preview {
    NotTodaySheet()
        .environment(AppServices.preview)
        .environment(AppState())
}
