import SwiftUI

enum MCOTheme {
    enum Color {
        static let paper = SwiftUI.Color(hex: 0xF7F1E8)
        static let paperRaised = SwiftUI.Color(hex: 0xFBF7EF)
        static let ink = SwiftUI.Color(hex: 0x221F1B)
        static let inkMuted = SwiftUI.Color(hex: 0x5D5750)
        static let hairline = SwiftUI.Color(hex: 0xD8CDBD)
        static let hairlineStrong = SwiftUI.Color(hex: 0xBFAF9B)
        static let oxblood = SwiftUI.Color(hex: 0x8E2D2C)
        static let oxbloodDark = SwiftUI.Color(hex: 0x6F1F1E)
        static let sage = SwiftUI.Color(hex: 0x7F8A6B)
        static let sageDeep = SwiftUI.Color(hex: 0x5E6A50)
        static let brass = SwiftUI.Color(hex: 0xB89A61)
        static let clay = SwiftUI.Color(hex: 0xA96E4D)
        static let liveBlue = SwiftUI.Color(hex: 0x2F6E8E)
        static let success = SwiftUI.Color(hex: 0x3F6F4F)
        static let warning = SwiftUI.Color(hex: 0x9C7A28)
        static let danger = SwiftUI.Color(hex: 0xA2433F)
    }
}

enum MCOType {
    static let display = Font.system(size: 42, weight: .regular, design: .serif)
    static let screenTitle = Font.system(size: 34, weight: .regular, design: .serif)
    static let cardTitle = Font.system(size: 25, weight: .regular, design: .serif)
    static let headline = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let bodySmall = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let tinyLabel = Font.system(size: 11, weight: .semibold)
}

enum MCOSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum MCOShape {
    static let blockRadius: CGFloat = 8
    static let controlRadius: CGFloat = 12
    static let commandRadius: CGFloat = 28
    static let pillRadius: CGFloat = 999
    static let imageRadius: CGFloat = 12
}

enum MCOGlass {
    static let commandTint = MCOTheme.Color.paperRaised.opacity(0.72)
}

extension SwiftUI.Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct EditorialScreen<Content: View, BottomBar: View>: View {
    let bottomContentPadding: CGFloat
    let showsBottomBar: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    init(
        bottomContentPadding: CGFloat = 120,
        showsBottomBar: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.bottomContentPadding = bottomContentPadding
        self.showsBottomBar = showsBottomBar
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        let screen = ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, MCOSpace.l)
                    .padding(.top, MCOSpace.l)
                    .padding(.bottom, bottomContentPadding)
            }
        }

        if showsBottomBar {
            screen.safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal, MCOSpace.m)
                    .padding(.bottom, MCOSpace.s)
            }
        } else {
            screen
        }
    }
}

struct JournalBlock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(MCOSpace.m)
            .background(MCOTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
            }
    }
}

struct GlassCommandBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: MCOSpace.s) {
            HStack(spacing: MCOSpace.s) {
                content
            }
            .padding(MCOSpace.s)
            .frame(maxWidth: .infinity)
            .glassEffect(
                .regular.tint(MCOGlass.commandTint),
                in: .rect(cornerRadius: MCOShape.commandRadius)
            )
        }
    }
}

struct FloatingIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MCOTheme.Color.ink)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MCOSpace.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(MCOTheme.Color.paperRaised)
            .background(
                LinearGradient(
                    colors: [MCOTheme.Color.oxblood, MCOTheme.Color.oxbloodDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(MCOTheme.Color.ink)
                .background(MCOTheme.Color.paperRaised.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct StatusChip: View {
    let text: String
    var tone: ChipTone = .quiet

    var body: some View {
        Text(text)
            .font(MCOType.caption)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, MCOSpace.s)
            .padding(.vertical, 6)
            .background(tone.background)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(tone.stroke, lineWidth: 1)
            }
    }
}

enum ChipTone: Equatable {
    case quiet
    case ready
    case warning
    case info
    case danger

    var foreground: Color {
        switch self {
        case .quiet: MCOTheme.Color.inkMuted
        case .ready: MCOTheme.Color.success
        case .warning: MCOTheme.Color.warning
        case .info: MCOTheme.Color.liveBlue
        case .danger: MCOTheme.Color.danger
        }
    }

    var background: Color {
        foreground.opacity(0.08)
    }

    var stroke: Color {
        foreground.opacity(0.35)
    }
}

struct FolioRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            leading
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
            }
            Spacer(minLength: MCOSpace.s)
            trailing
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(MCOTheme.Color.hairline)
            .frame(height: 1)
    }
}

struct ActionFeedbackBanner: View {
    let message: String?
    var tone: ChipTone = .info

    var body: some View {
        if let message = message?.nilIfBlank {
            HStack(alignment: .center, spacing: MCOSpace.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(MCOType.bodySmall)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: MCOSpace.s)
            }
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, MCOSpace.m)
            .padding(.vertical, MCOSpace.s)
            .background(tone.background)
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                    .stroke(tone.stroke, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var systemImage: String {
        switch tone {
        case .quiet:
            "info.circle"
        case .ready:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .info:
            "dot.radiowaves.left.and.right"
        case .danger:
            "xmark.octagon.fill"
        }
    }
}
