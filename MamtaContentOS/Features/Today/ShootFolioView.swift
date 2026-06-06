import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(AppServices.self) private var services
    @State private var selection: PackageSection = .scenes

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                sectionTabs

                switch selection {
                case .scenes:
                    SceneListView(scenes: services.todayCard.scenes)
                case .script:
                    CopyBlock(title: "Script", bodyText: services.todayCard.script ?? "Race week isn't about doing more. It's about doing what matters. Simple plan. Steady steps. Let's go.")
                case .caption:
                    CopyBlock(title: "Caption", bodyText: services.todayCard.caption ?? "Race week has entered the house. Keeping it simple, steady, and real today.")
                case .audio:
                    CopyBlock(title: "Audio", bodyText: services.todayCard.audioOptionNotes ?? "Calm Drive - Instrumental - fallback ready")
                case .post:
                    CopyBlock(title: "Post", bodyText: services.todayCard.postInstructions ?? "Open Instagram, use the saved audio if available, add cover text: Race week mindset.")
                }
            }
        } bottomBar: {
            GlassCommandBar {
                PrimaryActionButton(title: "Mark shot", systemImage: "checkmark.seal") {
                    services.completeToday(with: DailyDecision.shot)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            Text("Shoot Folio")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Spacer()
            FloatingIconButton(systemImage: "ellipsis", label: "More") {}
        }
    }

    private var sectionTabs: some View {
        HStack(spacing: MCOSpace.m) {
            ForEach(PackageSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: MCOSpace.xs) {
                        Text(section.rawValue)
                            .font(MCOType.bodySmall)
                            .foregroundStyle(selection == section ? MCOTheme.Color.oxblood : MCOTheme.Color.inkMuted)
                        Rectangle()
                            .fill(selection == section ? MCOTheme.Color.oxblood : .clear)
                            .frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SceneListView: View {
    let scenes: [ShotScene]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(scenes) { scene in
                FolioRow(title: scene.title, subtitle: nil) {
                    Text(String(format: "%02d", scene.number))
                        .font(.system(size: 46, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.sageDeep)
                } trailing: {
                    HStack(spacing: MCOSpace.s) {
                        StatusChip(text: scene.duration)
                        Image(systemName: scene.symbol)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(MCOTheme.Color.brass)
                            .frame(width: 54, height: 54)
                            .background(MCOTheme.Color.paperRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Hairline()
            }
        }
    }
}

struct CopyBlock: View {
    let title: String
    let bodyText: String
    @State private var didCopy = false

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                Text(title)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(bodyText)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineSpacing(5)
                SecondaryActionButton(title: didCopy ? "Copied" : "Copy \(title.lowercased())") {
                    copyBodyText()
                }
            }
        }
        .onChange(of: bodyText) {
            didCopy = false
        }
    }

    private func copyBodyText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = bodyText
        #endif
        didCopy = true
    }
}

#Preview {
    NavigationStack {
        ShootFolioView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
