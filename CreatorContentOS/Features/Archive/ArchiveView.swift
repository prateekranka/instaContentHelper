import SwiftUI

struct ArchiveView: View {
    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                ArchiveSection()
                    .padding(PocketSheetSpace.l)
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
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Archive")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Past decisions and outputs.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
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
                    .buttonStyle(.plain)
                    PocketSheetDivider()
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            ArchiveEntryDetailView(entry: entry)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var filteredEntries: [ArchiveEntry] {
        services.archiveEntries.filter { selectedFilter.includes($0) }
    }
}

private enum ArchiveFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case posted = "Shot & posted"
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PocketSheetSpace.s) {
                ForEach(ArchiveFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(PocketSheetType.chip)
                            .foregroundStyle(
                                selectedFilter == filter
                                    ? PocketSheetTheme.Color.inversePaper
                                    : PocketSheetTheme.Color.ink
                            )
                            .padding(.horizontal, PocketSheetSpace.s)
                            .frame(height: 32)
                            .background(
                                selectedFilter == filter
                                    ? PocketSheetTheme.Color.inverseInk
                                    : PocketSheetTheme.Color.fillMuted
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ArchiveTimelineRow: View {
    let entry: ArchiveEntry

    var body: some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.m) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text(entry.day)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(entry.date)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .frame(width: 56, alignment: .leading)

            Rectangle()
                .fill(PocketSheetTheme.Color.hairline)
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text(entry.cardTitle)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(entry.outputLine)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }

            Spacer()

            if entry.hasPostThumbnail {
                Image(systemName: "figure.run")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                    .frame(width: 54, height: 54)
                    .background(PocketSheetTheme.Color.inverseInk)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "chevron.right")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
            }
        }
        .padding(.vertical, PocketSheetSpace.m)
    }
}

private struct ArchiveEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ArchiveEntry

    var body: some View {
        NavigationStack {
            ZStack {
                PocketSheetTheme.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                        Text("\(entry.day), \(entry.date)")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                        Text(entry.cardTitle)
                            .font(PocketSheetType.screenTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PocketSheetCard {
                        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                            PocketSheetStatus(
                                text: entry.decision.archiveLabel,
                                kind: entry.decision.isPositiveCompletion ? .ready : .pending
                            )
                            Text(entry.outputLine)
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.hasPostThumbnail ? "Post output was recorded." : "No post thumbnail was attached.")
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        }
                    }

                    Spacer()
                }
                .padding(PocketSheetSpace.l)
            }
            .tint(PocketSheetTheme.Color.ink)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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
