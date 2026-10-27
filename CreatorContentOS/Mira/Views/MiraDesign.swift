import SwiftUI
import UIKit

enum MiraTheme {
    static let paper = Color(
        UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.13, blue: 0.11, alpha: 1)
                : UIColor(red: 0.969, green: 0.961, blue: 0.937, alpha: 1)
        })
    static let ink = Color(
        UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.93, green: 0.94, blue: 0.90, alpha: 1)
                : UIColor(red: 0.14, green: 0.15, blue: 0.14, alpha: 1)
        })
    static let olive = Color(
        UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.75, green: 0.82, blue: 0.70, alpha: 1)
                : UIColor(red: 0.275, green: 0.337, blue: 0.263, alpha: 1)
        })
}
struct MiraPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(MiraTheme.paper).background(
                MiraTheme.olive.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 10))
    }
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
            TextField(title, text: $text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(
                2...10
            )
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
    case adjustIdea(UUID, UUID)
    case brief(UUID)
    case manualIdea(UUID)
    var id: String {
        switch self {
        case .profile: "profile"
        case .ask(let id, let operation, let target):
            "ask-\(id)-\(operation)-\(String(describing:target))"
        case .adjustIdea(let id, let idea): "adjust-\(id)-\(idea)"
        case .brief(let id): "brief-\(id)"
        case .manualIdea(let id): "idea-\(id)"
        }
    }
}
