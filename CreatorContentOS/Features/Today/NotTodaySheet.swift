import SwiftUI

struct NotTodaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @State private var detail: BackupDetail?

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
                        .font(MCOType.dateLine)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                .padding(.top, MCOSpace.l)

                VStack(spacing: MCOSpace.m) {
                    BackupOptionRow(
                        symbol: "10.circle",
                        title: "10-second story",
                        subtitle: backupStorySubtitle
                    ) {
                        detail = .story
                    }
                    BackupOptionRow(
                        symbol: "feather",
                        title: "Caption-only post",
                        subtitle: backupCaptionSubtitle
                    ) {
                        detail = .captionOnly
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
                    Button {
                        complete(.skippedIntentionally)
                    } label: {
                        Text("Skip intentionally")
                            .font(MCOType.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .background(MCOTheme.Color.paperRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MCOSpace.l)
            .padding(.top, MCOSpace.l)
            .padding(.bottom, MCOSpace.l)
        }
        .sheet(item: $detail) { detail in
            BackupDecisionSheet(detail: detail) {
                complete(detail.decision)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var backupStorySubtitle: String {
        services.todayCard.backupStory?.nilIfBlank.map { _ in "Keep the streak alive." }
            ?? "Keep the streak alive."
    }

    private var backupCaptionSubtitle: String {
        services.todayCard.backupCaptionOnly?.nilIfBlank.map { _ in "Share the thought." }
            ?? "Share the thought."
    }

    private func complete(_ decision: DailyDecision) {
        services.completeToday(with: decision)
        services.lastActionMessage = decision.confirmationMessage
        dismiss()
    }
}

/// Which backup the creator tapped. Opening the sheet does NOT record a
/// decision — only tapping `Use backup` inside it does.
private enum BackupDetail: Identifiable, Hashable {
    case story
    case captionOnly

    var id: String {
        switch self {
        case .story: "story"
        case .captionOnly: "caption-only"
        }
    }

    var decision: DailyDecision {
        switch self {
        case .story: .backupStory
        case .captionOnly: .captionOnly
        }
    }
}

private struct BackupDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let detail: BackupDetail
    let onUseBackup: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        VStack(alignment: .leading, spacing: MCOSpace.xs) {
                            Text(eyebrow)
                                .font(MCOType.tinyLabel)
                                .foregroundStyle(MCOTheme.Color.oxblood)
                            Text(title)
                                .font(MCOType.screenTitle)
                                .foregroundStyle(MCOTheme.Color.ink)
                            Text(subtitle)
                                .font(MCOType.dateLine)
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                        }

                        if let primary = primaryText?.nilIfBlank {
                            BackupCopyBlock(label: primaryLabel, text: primary)
                        }
                        if let visual = visualDirection?.nilIfBlank {
                            BackupCopyBlock(label: "Visual direction", text: visual)
                        }
                        if let textDirection = textDirection?.nilIfBlank {
                            BackupCopyBlock(label: textDirectionLabel, text: textDirection)
                        }
                        if let context = creatorContext?.nilIfBlank {
                            BackupCopyBlock(label: "Context", text: context)
                        }

                        Spacer(minLength: MCOSpace.m)

                        PrimaryActionButton(title: "Use backup", systemImage: "checkmark.seal") {
                            onUseBackup()
                            dismiss()
                        }
                    }
                    .padding(MCOSpace.l)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MCOTheme.Color.oxblood)
                }
            }
        }
    }

    private var card: DailyCard { services.todayCard }

    private var eyebrow: String {
        detail == .story ? "BACKUP" : "BACKUP"
    }

    private var title: String {
        detail == .story ? "10-second story" : "Caption-only post"
    }

    private var subtitle: String {
        detail == .story
            ? "A real, usable backup you can post as a story right now."
            : "A real, usable caption you can post without new footage."
    }

    private var primaryLabel: String {
        detail == .story ? "Backup story" : "Caption"
    }

    private var primaryText: String? {
        detail == .story ? card.backupStory : card.backupCaptionOnly ?? card.caption
    }

    private var visualDirection: String? {
        switch detail {
        case .story:
            card.postInstructions ?? card.coverText
        case .captionOnly:
            card.postInstructions ?? card.coverText
        }
    }

    private var textDirectionLabel: String {
        detail == .story ? "Text / on-screen direction" : "Posting note"
    }

    private var textDirection: String? {
        switch detail {
        case .story:
            if let onScreen = card.onScreenTextTimeline?.first?.onScreenText?.nilIfBlank {
                return onScreen
            }
            return card.coverText ?? card.onScreenText?.first
        case .captionOnly:
            return card.cta
        }
    }

    private var creatorContext: String? {
        card.whyToday.nilIfBlank ?? card.sourceNote
    }
}

private struct BackupCopyBlock: View {
    let label: String
    let text: String
    @State private var didCopy = false

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text(label.uppercased())
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(text)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryActionButton(title: didCopy ? "Copied" : "Copy") {
                    copy()
                }
            }
        }
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        didCopy = true
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
                        .font(MCOType.iconEmpty)
                        .foregroundStyle(MCOTheme.Color.brass)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                        Text(title)
                            .font(MCOType.editorialHeadline)
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

#if canImport(UIKit)
import UIKit
#endif

#Preview {
    NotTodaySheet()
        .environment(AppServices.preview)
        .environment(AppState())
}
