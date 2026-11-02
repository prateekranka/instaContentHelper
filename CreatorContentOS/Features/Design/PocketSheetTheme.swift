import SwiftUI
import UIKit

/// Creator-only monochrome Pocket Sheet palette. Do not use in Manager/Admin shells.
enum PocketSheetTheme {
    enum Color {
        static let paper = SwiftUI.Color(hex: 0xFAFAFA)
        static let paperRaised = SwiftUI.Color(hex: 0xFFFFFF)
        static let ink = SwiftUI.Color(hex: 0x000000)
        static let inkMuted = SwiftUI.Color(hex: 0x666666)
        static let inkQuiet = inkMuted
        static let hairline = SwiftUI.Color(hex: 0xE5E5E5)
        static let hairlineSoft = SwiftUI.Color(hex: 0xF0F0F0)
        static let fillMuted = SwiftUI.Color(hex: 0xF5F5F5)
        static let inversePaper = SwiftUI.Color(hex: 0xFFFFFF)
        static let inverseInk = ink
        /// Creator validation attention stays in the monochrome semantic palette.
        static let validationAttention = ink
        /// Monochrome calendar / status dots (ready).
        static let statusReady = ink
        /// Monochrome calendar / status dots (draft).
        static let statusDraft = SwiftUI.Color(hex: 0xA3A3A3)
    }
}

// MARK: - Shared chrome palette (Creator Pocket Sheet vs Admin editorial)

/// Semantic colors for views shared between Creator (Pocket Sheet) and Admin (editorial).
struct ChromePalette: Equatable {
    var paper: Color
    var paperRaised: Color
    var ink: Color
    var inkMuted: Color
    var inkQuiet: Color
    var hairline: Color
    var hairlineStrong: Color
    var accent: Color
    var accentSecondary: Color
    var validationAttention: Color
    var statusReady: Color
    var statusDraft: Color
    var statusInfo: Color
    var statusPositive: Color

    static let editorial = ChromePalette(
        paper: MCOTheme.Color.paper,
        paperRaised: MCOTheme.Color.paperRaised,
        ink: MCOTheme.Color.ink,
        inkMuted: MCOTheme.Color.inkMuted,
        inkQuiet: MCOTheme.Color.inkMuted,
        hairline: MCOTheme.Color.hairline,
        hairlineStrong: MCOTheme.Color.hairlineStrong,
        accent: MCOTheme.Color.oxblood,
        accentSecondary: MCOTheme.Color.brass,
        validationAttention: MCOTheme.Color.danger,
        statusReady: MCOTheme.Color.success,
        statusDraft: MCOTheme.Color.warning,
        statusInfo: MCOTheme.Color.liveBlue,
        statusPositive: MCOTheme.Color.sageDeep
    )

    static let pocketSheet = ChromePalette(
        paper: PocketSheetTheme.Color.paper,
        paperRaised: PocketSheetTheme.Color.paperRaised,
        ink: PocketSheetTheme.Color.ink,
        inkMuted: PocketSheetTheme.Color.inkMuted,
        inkQuiet: PocketSheetTheme.Color.inkQuiet,
        hairline: PocketSheetTheme.Color.hairline,
        hairlineStrong: PocketSheetTheme.Color.hairline,
        accent: PocketSheetTheme.Color.inverseInk,
        accentSecondary: PocketSheetTheme.Color.inkMuted,
        validationAttention: PocketSheetTheme.Color.validationAttention,
        statusReady: PocketSheetTheme.Color.statusReady,
        statusDraft: PocketSheetTheme.Color.statusDraft,
        statusInfo: PocketSheetTheme.Color.ink,
        statusPositive: PocketSheetTheme.Color.ink
    )
}

private struct ChromePaletteKey: EnvironmentKey {
    static let defaultValue = ChromePalette.editorial
}

extension EnvironmentValues {
    var chromePalette: ChromePalette {
        get { self[ChromePaletteKey.self] }
        set { self[ChromePaletteKey.self] = newValue }
    }
}

extension View {
    /// Pocket Sheet monochrome palette for Creator shell descendants.
    func pocketSheetChromePalette() -> some View {
        environment(\.chromePalette, .pocketSheet)
    }
}

extension EnvironmentValues {
    /// Real system preference, plus a DEBUG-only deterministic test override.
    var pocketReduceMotion: Bool {
        accessibilityReduceMotion || DebugLaunchFlags.forceReducedMotion
    }
}

enum PocketSheetType {
    case screenTitle, sectionTitle, sectionLabel, rowTitle, rowSubtitle
    case bodyText, chip, actionPrimary, actionSecondary, status, navIcon, listIcon

    var size: CGFloat {
        switch self {
        case .screenTitle, .sectionTitle: 18
        case .rowTitle, .bodyText, .chip, .actionPrimary, .actionSecondary: 16
        case .sectionLabel, .rowSubtitle, .status: 14
        case .navIcon: 24
        case .listIcon: 28
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenTitle, .sectionTitle, .rowTitle, .actionPrimary, .actionSecondary: .medium
        default: .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .screenTitle, .sectionTitle: .headline
        case .sectionLabel, .rowSubtitle, .status: .footnote
        default: .body
        }
    }
}

private struct PocketSheetFontModifier: ViewModifier {
    let style: PocketSheetType
    @ScaledMetric private var size: CGFloat

    init(style: PocketSheetType) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(Font.system(size: size, weight: style.weight))
    }
}

extension View {
    func font(_ style: PocketSheetType) -> some View {
        modifier(PocketSheetFontModifier(style: style))
    }
}

enum Spacing {
    static let section: CGFloat = 28
}

enum PocketSheetSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let section = Spacing.section
}

enum PocketSheetShape {
    static let sheetRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let pillRadius: CGFloat = 999
}

// MARK: - Tab bar

/// Monochrome Creator tab bar styling (prototype `.tabs` / `.tab`).
@MainActor
enum PocketSheetTabBarAppearance {
    static func makeAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(PocketSheetTheme.Color.paper)
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor(PocketSheetTheme.Color.hairline)
        appearance.shadowImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear
        appearance.selectionIndicatorImage = UIImage()

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(PocketSheetTheme.Color.inkMuted)
        itemAppearance.normal.titleTextAttributes = tabTitleAttributes(
            color: PocketSheetTheme.Color.inkMuted,
            weight: .medium
        )
        itemAppearance.selected.iconColor = UIColor(PocketSheetTheme.Color.ink)
        itemAppearance.selected.titleTextAttributes = tabTitleAttributes(
            color: PocketSheetTheme.Color.ink,
            weight: .medium
        )

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance
        return appearance
    }

    static func apply(to tabBar: UITabBar) {
        let appearance = makeAppearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor(PocketSheetTheme.Color.ink)
        tabBar.unselectedItemTintColor = UIColor(PocketSheetTheme.Color.inkMuted)
        tabBar.isTranslucent = false
        tabBar.barTintColor = UIColor(PocketSheetTheme.Color.paper)
    }

    private static func tabTitleAttributes(
        color: SwiftUI.Color,
        weight: UIFont.Weight
    ) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: UIColor(color),
            .font: UIFontMetrics(forTextStyle: .caption2)
                .scaledFont(for: UIFont.systemFont(ofSize: 14, weight: weight)),
        ]
    }
}

private struct PocketSheetTabBarConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let tabBar = uiViewController.tabBarController?.tabBar else { return }
            PocketSheetTabBarAppearance.apply(to: tabBar)
        }
    }
}

extension View {
    /// Paper tab bar, ink selected state, muted unselected — Creator shell only.
    func pocketSheetTabBarChrome() -> some View {
        tint(PocketSheetTheme.Color.ink)
            .toolbarBackground(PocketSheetTheme.Color.paper, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .background(PocketSheetTabBarConfigurator())
    }
}
