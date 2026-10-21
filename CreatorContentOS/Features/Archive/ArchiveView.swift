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
        VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Archive")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Past decisions and outputs.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }

            ArchiveFilterBar(selectedFilter: $selectedFilter)

            LazyVStack(spacing: 0) {
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
            .background(PocketSheetTheme.Color.fillMuted)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
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
                            .font(PocketSheetType.actionSecondary)
                            .foregroundStyle(
                                selectedFilter == filter
                                    ? PocketSheetTheme.Color.inversePaper
                                    : PocketSheetTheme.Color.ink
                            )
                            .padding(.horizontal, PocketSheetSpace.xxs)
                            .padding(.horizontal, PocketSheetSpace.m)
                            .padding(.vertical, PocketSheetSpace.xxs)
                            .frame(minHeight: 44)
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
        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            Image(systemName: entry.hasPostThumbnail ? "figure.run" : "tray")
                .font(PocketSheetType.listIcon)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text(entry.cardTitle)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("\(entry.day.capitalized), \(entry.date.capitalized)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text(entry.outputLine)
                    .accessibilityIdentifier("archive.output.\(entry.cardTitle)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(PocketSheetType.navIcon)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.vertical, PocketSheetSpace.s)
    }
}

private struct ArchiveEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ArchiveEntry

    var body: some View {
        NavigationStack {
            ZStack {
                PocketSheetTheme.Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                        Text("\(entry.day.capitalized), \(entry.date.capitalized)")
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
                    .font(PocketSheetType.actionSecondary)
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
