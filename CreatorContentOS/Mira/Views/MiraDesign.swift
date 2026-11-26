import SwiftUI
import UIKit

enum MiraTheme {
    private static func gray(light: CGFloat, dark: CGFloat) -> Color {
        Color(
            UIColor {
                let value = $0.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: value, green: value, blue: value, alpha: 1)
            })
    }
    static let paper = gray(light: 0.965, dark: 0.0)
    static let surface = gray(light: 1.0, dark: 0.11)
    static let field = gray(light: 1.0, dark: 0.15)
    static let edge = gray(light: 0.62, dark: 0.45)
    static let ink = gray(light: 0.08, dark: 0.96)
    static let secondaryInk = gray(light: 0.36, dark: 0.70)
    static let accent = ink
}
struct MiraPrimaryStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(MiraTheme.paper).background(
                MiraTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: configuration.isPressed)
    }
}
struct MiraFieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).foregroundStyle(MiraTheme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(MiraTheme.field, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MiraTheme.edge, lineWidth: 1))
    }
}
extension View {
    func miraFieldBox() -> some View { modifier(MiraFieldBox()) }
}
struct MiraPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }.frame(maxWidth: 680, alignment: .leading)
                .padding(24).frame(maxWidth: .infinity)
        }
        .background(MiraTheme.paper).foregroundStyle(MiraTheme.ink)
    }
}
struct MiraField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(title, text: $text, axis: .vertical).lineLimit(2...10)
                .miraFieldBox()
                .accessibilityLabel(title)
        }
    }
}
struct MiraSectionTitle: View {
    var text: String
    var body: some View {
        Text(text).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }
}
enum MiraSheet: Identifiable {
    case profile
    case ask(UUID, MiraOperation, UUID?)
    case askToday(UUID, UUID)
    case todayScript(UUID, UUID)
    case adjustIdea(UUID, UUID)
    case brief(UUID)
    case manualIdea(UUID)
    var id: String {
        switch self {
        case .profile: "profile"
        case .ask(let id, let operation, let target):
            "ask-\(id)-\(operation)-\(String(describing:target))"
        case .askToday(let id, let card): "ask-today-\(id)-\(card)"
        case .todayScript(let id, let card): "today-script-\(id)-\(card)"
        case .adjustIdea(let id, let idea): "adjust-\(id)-\(idea)"
        case .brief(let id): "brief-\(id)"
        case .manualIdea(let id): "idea-\(id)"
        }
    }
}
