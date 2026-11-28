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
private struct MiraInputFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension EnvironmentValues {
    @Entry var miraTabBarClearance: CGFloat = 0
    @Entry var miraInputFocus: FocusState<UUID?>.Binding? = nil
}
private enum MiraInputSpace {
    static let name = "mira.page.inputs"
}
struct MiraPage<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.miraTabBarClearance) private var tabBarClearance
    @FocusState private var focusedInput: UUID?
    @State private var inputFrames: [UUID: CGRect] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }.frame(maxWidth: 680, alignment: .leading)
                .padding(24).frame(maxWidth: .infinity)
                .environment(\.miraInputFocus, $focusedInput)
        }
        .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
        .background(MiraTheme.paper).foregroundStyle(MiraTheme.ink)
        .contentShape(Rectangle())
        .coordinateSpace(.named(MiraInputSpace.name))
        .onPreferenceChange(MiraInputFrames.self) { inputFrames = $0 }
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named(MiraInputSpace.name)).onEnded { tap in
                if !inputFrames.values.contains(where: { $0.contains(tap.location) }) {
                    focusedInput = nil
                }
            },
            isEnabled: focusedInput != nil)
    }
}
struct MiraTextInput: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var boxed = true
    @Environment(\.miraInputFocus) private var pageFocus
    @FocusState private var localFocus: UUID?
    @State private var id = UUID()

    private var focus: FocusState<UUID?>.Binding { pageFocus ?? $localFocus }

    var body: some View {
        Group {
            if boxed { field.miraFieldBox() } else { field }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MiraInputFrames.self, value: [id: geometry.frame(in: .named(MiraInputSpace.name))])
            }.allowsHitTesting(false)
        }
    }

    private var field: some View {
        TextField(title, text: Binding(get: { text }, set: { newValue in update(newValue) }), axis: axis)
            .submitLabel(.done)
            .focused(focus, equals: id)
            .onSubmit { focus.wrappedValue = nil }
    }

    private func update(_ value: String) {
        if axis == .vertical, focus.wrappedValue == id, value.contains("\n") {
            let insertions = value.difference(from: text).insertions
            if insertions.count == 1, case .insert(_, "\n", _)? = insertions.first {
                focus.wrappedValue = nil
                return
            }
        }
        text = value
    }
}
struct MiraField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            MiraTextInput(title: title, text: $text, axis: .vertical).lineLimit(2...10)
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
    case ask(UUID, MiraOperation, UUID?, note: String = "")
    case askToday(UUID, UUID, note: String = "")
    case todayScript(UUID, UUID)
    case adjustIdea(UUID, UUID)
    case dealDraft(String)
    case brief(UUID)
    case manualIdea(UUID)
    var id: String {
        switch self {
        case .profile: "profile"
        case .ask(let id, let operation, let target, _):
            "ask-\(id)-\(operation)-\(String(describing:target))"
        case .askToday(let id, let card, _): "ask-today-\(id)-\(card)"
        case .todayScript(let id, let card): "today-script-\(id)-\(card)"
        case .adjustIdea(let id, let idea): "adjust-\(id)-\(idea)"
        case .dealDraft: "deal-draft"
        case .brief(let id): "brief-\(id)"
        case .manualIdea(let id): "idea-\(id)"
        }
    }
}

struct MiraFeedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MiraTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MiraTheme.edge, lineWidth: 1))
    }
}

struct MiraTaskHeading: View {
    let step: MiraTaskStep

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(step.number) / \(MiraTaskStep.total)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(MiraTheme.secondaryInk)
                .accessibilityIdentifier("mira.task.step")
            Text(step.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }
    }
}
