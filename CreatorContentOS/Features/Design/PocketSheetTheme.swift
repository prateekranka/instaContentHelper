import SwiftUI

/// Creator-only monochrome Pocket Sheet palette. Do not use in Manager/Admin shells.
enum PocketSheetTheme {
    enum Color {
        static let paper = SwiftUI.Color(hex: 0xFAFAFA)
        static let paperRaised = SwiftUI.Color(hex: 0xFFFFFF)
        static let ink = SwiftUI.Color(hex: 0x111111)
        static let inkMuted = SwiftUI.Color(hex: 0x737373)
        static let inkQuiet = SwiftUI.Color(hex: 0xA3A3A3)
        static let hairline = SwiftUI.Color(hex: 0xE5E5E5)
        static let hairlineSoft = SwiftUI.Color(hex: 0xF0F0F0)
        static let fillMuted = SwiftUI.Color(hex: 0xF5F5F5)
        static let inversePaper = SwiftUI.Color(hex: 0xFFFFFF)
        static let inverseInk = SwiftUI.Color(hex: 0x111111)
        /// Onboarding reference validation attention (prototype `data-attn` red).
        static let validationAttention = SwiftUI.Color(hex: 0xDC2626)
    }
}

enum PocketSheetType {
    static let screenTitle = Font.system(size: 28, weight: .semibold)
    static let sectionLabel = Font.system(size: 11, weight: .bold)
    static let rowTitle = Font.system(size: 14, weight: .semibold)
    static let rowSubtitle = Font.system(size: 12, weight: .regular)
    static let chip = Font.system(size: 11, weight: .semibold)
    static let actionPrimary = Font.system(size: 16, weight: .semibold)
    static let actionSecondary = Font.system(size: 16, weight: .medium)
    static let status = Font.system(size: 11, weight: .semibold)
}

enum PocketSheetSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
}

enum PocketSheetShape {
    static let sheetRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let pillRadius: CGFloat = 999
}
