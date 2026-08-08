import SwiftUI

// MARK: - Chrome-aware screen

/// Scroll shell that follows the active `chromePalette` (Creator Pocket Sheet vs Admin editorial).
struct ChromeScreen<Content: View, BottomBar: View>: View {
    @Environment(\.chromePalette) private var chrome
    let bottomContentPadding: CGFloat
    let showsBottomBar: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    init(
        bottomContentPadding: CGFloat = 120,
        showsBottomBar: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar = { EmptyView() }
    ) {
        self.bottomContentPadding = bottomContentPadding
        self.showsBottomBar = showsBottomBar
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        if chrome == .pocketSheet {
            PocketSheetScreen(
                bottomContentPadding: bottomContentPadding,
                showsBottomBar: showsBottomBar,
                content: { content },
                bottomBar: { bottomBar }
            )
        } else {
            EditorialScreen(
                bottomContentPadding: bottomContentPadding,
                showsBottomBar: showsBottomBar,
                content: { content },
                bottomBar: { bottomBar }
            )
        }
    }
}

// MARK: - Screen

struct PocketSheetScreen<Content: View, BottomBar: View>: View {
    let bottomContentPadding: CGFloat
    let showsBottomBar: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    init(
        bottomContentPadding: CGFloat = 120,
        showsBottomBar: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar = { EmptyView() }
    ) {
        self.bottomContentPadding = bottomContentPadding
        self.showsBottomBar = showsBottomBar
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        let screen = ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, PocketSheetSpace.l)
                    .padding(.top, PocketSheetSpace.l)
                    .padding(.bottom, bottomContentPadding)
            }
        }

        if showsBottomBar {
            screen.safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.bottom, PocketSheetSpace.s)
            }
        } else {
            screen
        }
    }
}

// MARK: - Card

struct PocketSheetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(PocketSheetSpace.m)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Command bar

struct PocketSheetCommandBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: PocketSheetSpace.xs) {
            content
        }
        .padding(PocketSheetSpace.s)
        .frame(maxWidth: .infinity)
        .background(PocketSheetTheme.Color.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Section title

struct PocketSheetSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            Text(title)
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Text(subtitle)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
        .padding(.top, PocketSheetSpace.xs)
    }
}

// MARK: - Feedback

struct PocketSheetFeedbackBanner: View {
    let message: String?
    var kind: PocketSheetStatusKind = .neutral

    var body: some View {
        if let message = message?.nilIfBlank {
            HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 14, weight: kind.symbolWeight))
                Text(message)
                    .font(PocketSheetType.rowSubtitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PocketSheetSpace.s)
            }
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.s)
            .background(PocketSheetTheme.Color.fillMuted)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Sheet

struct PocketSheetBlock<Content: View>: View {
    var header: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header.uppercased())
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    .tracking(0.44)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.top, PocketSheetSpace.s)
                    .padding(.bottom, PocketSheetSpace.xs)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .background(PocketSheetTheme.Color.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Row

struct PocketSheetRow: View {
    let title: String
    var subtitle: String?
    var trailingSymbol: String = "chevron.right"

    var body: some View {
        HStack(alignment: .center, spacing: PocketSheetSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
            }
            Spacer(minLength: PocketSheetSpace.s)
            Image(systemName: trailingSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
        }
        .frame(minHeight: 44, alignment: .center)
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
        .contentShape(Rectangle())
    }
}

// MARK: - Chip

struct PocketSheetChip: View {
    let text: String
    var isEmphasized: Bool = false

    var body: some View {
        Text(text)
            .font(PocketSheetType.chip)
            .foregroundStyle(isEmphasized ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(isEmphasized ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.fillMuted)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        isEmphasized ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.hairline,
                        lineWidth: 1
                    )
            }
            .accessibilityLabel(text)
    }
}

// MARK: - Divider

struct PocketSheetDivider: View {
    var body: some View {
        Rectangle()
            .fill(PocketSheetTheme.Color.hairlineSoft)
            .frame(height: 1)
    }
}

// MARK: - Actions

struct PocketSheetPrimaryAction: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSheetSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(PocketSheetType.actionPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
            .background(PocketSheetTheme.Color.inverseInk)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PocketSheetSecondaryAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PocketSheetType.actionSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status

enum PocketSheetStatusKind: Equatable {
    case neutral
    case ready
    case pending
    case issue

    var symbolName: String {
        switch self {
        case .neutral: "circle"
        case .ready: "checkmark.circle.fill"
        case .pending: "clock"
        case .issue: "exclamationmark.triangle.fill"
        }
    }

    var symbolWeight: Font.Weight {
        switch self {
        case .neutral: .regular
        case .ready: .semibold
        case .pending: .medium
        case .issue: .semibold
        }
    }
}

struct PocketSheetStatus: View {
    let text: String
    var kind: PocketSheetStatusKind = .neutral

    var body: some View {
        HStack(spacing: PocketSheetSpace.xs) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 12, weight: kind.symbolWeight))
            Text(text)
                .font(PocketSheetType.status)
        }
        .foregroundStyle(PocketSheetTheme.Color.ink)
        .padding(.horizontal, PocketSheetSpace.s)
        .frame(minHeight: 28)
        .background(PocketSheetTheme.Color.paper)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(accessibilityValue)")
    }

    private var accessibilityValue: String {
        switch kind {
        case .neutral: "neutral"
        case .ready: "ready"
        case .pending: "pending"
        case .issue: "issue"
        }
    }
}
