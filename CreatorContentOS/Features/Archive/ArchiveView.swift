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
    @State private var selectedFilter: ArchiveFilter = .all
    @State private var selectedEntry: ArchiveEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.l) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Archive")
                    .font(MCOType.screenTitle)
                    .tracking(MCOType.screenTitleTracking)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Past decisions and outputs.")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
            }

            ArchiveFilterBar(selectedFilter: $selectedFilter)

            VStack(spacing: 0) {
                ForEach(filteredEntries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        ArchiveTimelineRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable(scale: 0.99))
                    Hairline()
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            ArchiveEntryDetailView(entry: entry)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    private var filteredEntries: [ArchiveEntry] {
        services.archiveEntries.filter { selectedFilter.includes($0) }
    }
}

private enum ArchiveFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case posted = "Completed"
    case backup = "Backups"
    case skipped = "Skipped"

    var id: String { rawValue }

    func includes(_ entry: ArchiveEntry) -> Bool {
        switch self {
        case .all:
            true
        case .posted:
            entry.decision == .shot || entry.decision == .posted
        case .backup:
            entry.decision == .usedBackup
        case .skipped:
            entry.decision == .savedForTomorrow || entry.decision == .skippedIntentionally
        }
    }
}

private struct ArchiveFilterBar: View {
    @Binding var selectedFilter: ArchiveFilter

    var body: some View {
        FolioPillBar(
            items: ArchiveFilter.allCases.map { ($0, $0.rawValue) },
            selection: $selectedFilter,
            height: 32,
            font: MCOType.caption
        )
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
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .padding(.vertical, MCOSpace.m)
    }
}

private struct ArchiveEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ArchiveEntry

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: MCOSpace.l) {
                    VStack(alignment: .leading, spacing: MCOSpace.xs) {
                        Text("\(entry.day), \(entry.date)")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Text(entry.cardTitle)
                            .font(MCOType.screenTitle)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    JournalBlock {
                        VStack(alignment: .leading, spacing: MCOSpace.s) {
                            StatusChip(text: entry.decision.archiveLabel, tone: entry.decision.isPositiveCompletion ? .ready : .warning)
                            Text(entry.outputLine)
                                .font(MCOType.body)
                                .foregroundStyle(MCOTheme.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.hasPostThumbnail ? "Post output was recorded." : "No post thumbnail was attached.")
                                .font(MCOType.caption)
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                        }
                    }

                    Spacer()
                }
                .padding(MCOSpace.l)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MCOTheme.Color.oxblood)
                }
            }
        }
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
