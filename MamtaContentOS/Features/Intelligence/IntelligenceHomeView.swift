import SwiftUI

struct IntelligenceHomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: MCOSpace.l) {
                    header
                    IntelligenceShelf(
                        title: "Ready for this week",
                        items: services.intelligenceHome.readyForThisWeek
                    )
                    IntelligenceShelf(
                        title: "Needs your call",
                        items: services.intelligenceHome.needsReview
                    )
                    SourcePulseShelf(sourcePulse: services.intelligenceHome.sourcePulse)
                    IntelligenceShelf(
                        title: "Idea candidates",
                        items: services.intelligenceHome.ideaCandidates
                    )
                    IntelligenceShelf(
                        title: "Recently used",
                        items: services.intelligenceHome.recentlyUsed
                    )
                    LibraryNavigationShelf(sections: services.intelligenceHome.librarySections)
                }
                .padding(.horizontal, MCOSpace.l)
                .padding(.top, MCOSpace.l)
                .padding(.bottom, 116)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Text("MC")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 42, height: 42)
                    .background(MCOTheme.Color.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }

                Spacer()

                FloatingIconButton(systemImage: "line.3.horizontal.decrease", label: "Filter Intelligence") {}
                FloatingIconButton(systemImage: "ellipsis", label: "Back to Mamta Mode") {
                    appState.activeMode = .mamta
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("PRATEEK INTELLIGENCE")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text("Intelligence")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Prepared material for the week.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }
}

struct SourcePulseShelf: View {
    let sourcePulse: SourcePulseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: sourcePulse.title, trailing: sourcePulse.subtitle)

            VStack(spacing: 0) {
                ForEach(sourcePulse.references) { reference in
                    ReferencePulseRow(reference: reference)
                    Hairline()
                }
            }
        }
    }
}

struct ReferencePulseRow: View {
    let reference: ReferenceSummary

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: reference.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(reference.state.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(reference.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                Text("\(reference.sourceType) - \(reference.note)")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            StatusChip(text: reference.state.label, tone: reference.state.tone)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct IntelligenceShelf: View {
    let title: String
    let items: [IntelligenceItem]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: title, trailing: nil)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    IntelligenceShelfRow(item: item)
                    Hairline()
                }
            }
        }
    }
}

struct IntelligenceShelfRow: View {
    let item: IntelligenceItem

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(item.state.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(item.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(item.kind.rawValue)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.xs) {
                Text(item.trailingNote)
                    .font(MCOType.caption)
                    .foregroundStyle(item.state.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, MCOSpace.s)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryNavigationShelf: View {
    let sections: [IntelligenceLibrarySection]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "Library", trailing: "Counts stay secondary.")

            VStack(spacing: 0) {
                ForEach(sections) { section in
                    LibraryNavigationRow(section: section)
                    Hairline()
                }
            }
        }
    }
}

struct LibraryNavigationRow: View {
    let section: IntelligenceLibrarySection

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: section.symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(section.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(section.subtitle)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.s) {
                Text("\(section.count)")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct ShelfHeader: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Spacer(minLength: MCOSpace.s)
            if let trailing {
                Text(trailing)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }
        }
    }
}

extension IntelligenceReviewState {
    var accent: Color {
        switch self {
        case .ready, .approved:
            MCOTheme.Color.sageDeep
        case .needsReview:
            MCOTheme.Color.brass
        case .usedThisWeek:
            MCOTheme.Color.inkMuted
        }
    }

    var tone: ChipTone {
        switch self {
        case .ready, .approved:
            .ready
        case .needsReview:
            .warning
        case .usedThisWeek:
            .quiet
        }
    }
}

#Preview {
    IntelligenceHomeView()
        .environment(AppState())
        .environment(AppServices.preview)
}
