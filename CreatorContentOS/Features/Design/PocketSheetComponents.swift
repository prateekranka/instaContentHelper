import SwiftUI

/// Short press feedback for Pocket controls. Repeated reading surfaces stay still.
struct PocketSheetPressFeedbackStyle: ButtonStyle {
    @Environment(\.pocketReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Chrome-aware screen

/// Scroll shell that follows the active `chromePalette` (Creator Pocket Sheet vs Admin editorial).
struct ChromeScreen<Content: View, BottomBar: View>: View {
    @Environment(\.chromePalette) private var chrome
    let topContentPadding: CGFloat
    let bottomContentPadding: CGFloat
    let showsBottomBar: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    init(
        topContentPadding: CGFloat = PocketSheetSpace.l,
        bottomContentPadding: CGFloat = 120,
        showsBottomBar: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar = { EmptyView() }
    ) {
        self.topContentPadding = topContentPadding
        self.bottomContentPadding = bottomContentPadding
        self.showsBottomBar = showsBottomBar
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        if chrome == .pocketSheet {
            PocketSheetScreen(
                topContentPadding: topContentPadding,
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
    let topContentPadding: CGFloat
    let bottomContentPadding: CGFloat
    let showsBottomBar: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    init(
        topContentPadding: CGFloat = PocketSheetSpace.l,
        bottomContentPadding: CGFloat = 120,
        showsBottomBar: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar = { EmptyView() }
    ) {
        self.topContentPadding = topContentPadding
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
                    .padding(.top, topContentPadding)
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
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.vertical, PocketSheetSpace.s)
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
                    .font(PocketSheetType.rowSubtitle)
                Text(message)
                    .font(PocketSheetType.rowSubtitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PocketSheetSpace.s)
            }
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .padding(.horizontal, PocketSheetSpace.l)
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
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            if let header {
                Text(header)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PocketSheetTheme.Color.fillMuted)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
    }
}

// MARK: - Row

struct PocketSheetRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var subtitle: String?
    var trailingSymbol: String = "chevron.right"
    var leadingSymbol: String?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                    HStack(spacing: PocketSheetSpace.s) {
                        leadingIcon
                        Spacer(minLength: PocketSheetSpace.s)
                        trailingIcon
                    }
                    rowText
                }
            } else {
                HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                    leadingIcon
                    rowText
                    Spacer(minLength: PocketSheetSpace.s)
                    trailingIcon
                }
            }
        }
        .frame(minHeight: 44, alignment: .center)
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.vertical, PocketSheetSpace.s)
        .contentShape(Rectangle())
    }

    private var rowText: some View {
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let leadingSymbol {
            Image(systemName: leadingSymbol)
                .font(PocketSheetType.listIcon)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityHidden(true)
        }
    }

    private var trailingIcon: some View {
        Image(systemName: trailingSymbol)
            .font(PocketSheetType.navIcon)
            .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
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
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.xxs)
            .frame(minHeight: 44)
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
    @Environment(\.pocketReduceMotion) private var reduceMotion
    let title: String
    var systemImage: String?
    var animatesSymbol = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .contentTransition(animatesSymbol
                            ? (reduceMotion ? .opacity : .symbolEffect(.replace, options: .speed(4)))
                            : .identity)
                        .animation(animatesSymbol ? .easeOut(duration: 0.2) : nil, value: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .padding(.horizontal, PocketSheetSpace.xxs)
            }
            .font(PocketSheetType.actionPrimary)
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.xxs)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
            .background(PocketSheetTheme.Color.inverseInk)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        }
        .buttonStyle(PocketSheetPressFeedbackStyle())
    }
}

struct PocketSheetSecondaryAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PocketSheetType.actionSecondary)
                .padding(.horizontal, PocketSheetSpace.xxs)
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.vertical, PocketSheetSpace.xxs)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(PocketSheetPressFeedbackStyle())
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
        case .ready: .medium
        case .pending: .medium
        case .issue: .medium
        }
    }
}

struct PocketSheetStatus: View {
    let text: String
    var kind: PocketSheetStatusKind = .neutral

    var body: some View {
        HStack(spacing: PocketSheetSpace.xs) {
            Image(systemName: kind.symbolName)
                .font(PocketSheetType.rowSubtitle)
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
