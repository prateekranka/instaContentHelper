import SwiftUI

struct NotTodaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var detail: BackupDetail?

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: PocketSheetSpace.l) {
                    VStack(spacing: PocketSheetSpace.s) {
                        Text("Other ideas")
                            .font(PocketSheetType.screenTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Rectangle()
                            .fill(PocketSheetTheme.Color.hairline)
                            .frame(width: 32, height: 1)
                        Text("Choose the smallest useful win.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                    .padding(.top, PocketSheetSpace.l)

                    VStack(spacing: PocketSheetSpace.m) {
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
                            title: "Plan tomorrow",
                            subtitle: "Open tomorrow's plan and choose a real package."
                        ) {
                            planTomorrow()
                        }
                    }

                    Spacer()

                    PocketSheetSecondaryAction(title: "Skip intentionally") {
                        complete(.skippedIntentionally)
                    }
                }
                .padding(PocketSheetSpace.l)
                .padding(.top, PocketSheetSpace.l)
                .padding(.bottom, PocketSheetSpace.l)
            }
        }
        .sheet(item: $detail) { detail in
            BackupDecisionSheet(detail: detail) {
                complete(detail.decision)
            }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var backupStorySubtitle: String {
        services.todayCard.backupStory?.nilIfBlank ?? ""
    }

    private var backupCaptionSubtitle: String {
        services.todayCard.backupCaptionOnly?.nilIfBlank ?? ""
    }

    private func complete(_ decision: DailyDecision) {
        services.completeToday(with: decision)
        services.lastActionMessage = decision.confirmationMessage
        dismiss()
    }

    private func planTomorrow() {
        let tomorrow = SupabaseDateFormatting.dateOptions(
            starting: services.currentTodayDateString,
            dayCount: 2
        )[safe: 1] ?? services.currentTodayDateString
        appState.preparePlan(selecting: tomorrow)
        appState.pendingCreatorTab = .plan
        dismiss()
    }
}

/// Which backup the creator tapped. Opening the sheet does NOT record a
/// decision. The creator must explicitly confirm they posted the backup.
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
                PocketSheetTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                            Text(eyebrow)
                                .font(PocketSheetType.sectionLabel)
                                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                            Text(title)
                                .font(PocketSheetType.screenTitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            Text(subtitle)
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                                .lineLimit(3)
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

                        Spacer(minLength: PocketSheetSpace.m)

                        Text("Post this in your usual app. Your main idea stays in Today.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        PocketSheetPrimaryAction(title: "I've posted this backup", systemImage: "checkmark.seal") {
                            onUseBackup()
                            dismiss()
                        }
                        .accessibilityIdentifier("backup.confirmPosted")
                    }
                    .padding(PocketSheetSpace.l)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(PocketSheetTheme.Color.ink)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
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
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text(label.uppercased())
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                Text(text)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                PocketSheetSecondaryAction(title: didCopy ? "Copied" : "Copy") {
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
            PocketSheetCard {
                HStack(spacing: PocketSheetSpace.m) {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        Text(title)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
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
