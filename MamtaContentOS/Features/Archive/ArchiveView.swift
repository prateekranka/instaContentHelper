import SwiftUI

struct ArchiveView: View {
    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                ArchiveSection()
                    .padding(MCOSpace.l)
            }
        }
        .navigationBarHidden(true)
    }
}

struct ArchiveSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.l) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Archive")
                    .font(MCOType.screenTitle)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Decisions and outputs.")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
            }

            Hairline()

            VStack(spacing: 0) {
                ForEach(services.archiveEntries) { entry in
                    ArchiveTimelineRow(entry: entry)
                    Hairline()
                }
            }
        }
    }
}

struct ArchiveTimelineRow: View {
    let entry: ArchiveEntry

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.m) {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(entry.day)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(entry.date)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(width: 56, alignment: .leading)

            Rectangle()
                .fill(MCOTheme.Color.hairline)
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(entry.cardTitle)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(entry.outputLine)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(entry.decision.isPositiveCompletion ? MCOTheme.Color.sageDeep : MCOTheme.Color.brass)
            }

            Spacer()

            if entry.hasPostThumbnail {
                Image(systemName: "figure.run")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .frame(width: 54, height: 54)
                    .background(MCOTheme.Color.brass)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.vertical, MCOSpace.m)
    }
}

private extension CompletionState {
    var isPositiveCompletion: Bool {
        self == .shot || self == .posted
    }
}

#Preview {
    ArchiveView()
        .environment(AppServices.preview)
        .environment(AppState())
}
