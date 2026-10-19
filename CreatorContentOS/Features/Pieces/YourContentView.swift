import SwiftUI

enum YourContentFilter: String, CaseIterable, Identifiable {
    case all
    case draft
    case approved
    case shot
    case posted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .draft: "Draft"
        case .approved: "Approved"
        case .shot: "Shot"
        case .posted: "Posted"
        }
    }

    func includes(_ piece: ContentPiece) -> Bool {
        switch self {
        case .all: true
        case .draft: piece.needsReview
        case .approved: piece.stage == .approved
        case .shot: piece.stage == .shot
        case .posted: piece.stage == .posted
        }
    }
}

struct PieceDateGroup: Identifiable {
    let date: String
    let pieces: [ContentPiece]

    var id: String { date }
}

struct YourContentView: View {
    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var filter: YourContentFilter = .all
    @State private var composer: PieceComposerRequest?

    var body: some View {
        PieceScreen(title: "Your content") {
            PieceLargeTitle(title: "Your content")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PocketSheetSpace.xs) {
                    ForEach(YourContentFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(filter == option ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
                                .padding(.horizontal, PocketSheetSpace.m)
                                .frame(minHeight: 44)
                                .background(
                                    filter == option ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.paperRaised,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: filter == option ? 0 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                        .accessibilityIdentifier("content.filter.\(option.rawValue)")
                    }
                }
            }
            if groups.isEmpty {
                ContentUnavailableView(
                    query.isBlankText ? "Nothing here yet" : "No matches",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(query.isBlankText ? "Content you create appears here by date." : "Try another word or filter.")
                )
                .accessibilityIdentifier("content.empty")
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    HStack {
                        Text(PieceDates.longLabel(group.date))
                            .font(.headline)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Spacer()
                        Text(group.pieces.count == 1 ? "1 piece" : "\(group.pieces.count) pieces")
                            .font(.footnote)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(group.pieces) { piece in
                        NavigationLink(value: PieceRoute.piece(piece.id)) {
                            PieceRowView(piece: piece)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("content.piece.\(piece.title)")
                    }
                }
            }
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: "Add content") {
                    composer = PieceComposerRequest(date: services.currentTodayDateString)
                }
                .accessibilityIdentifier("content.add")
            }
        }
        .searchable(text: $query, prompt: "Search content")
        .sheet(item: $composer) { request in
            PieceComposerSheet(request: request)
        }
    }

    private var groups: [PieceDateGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = services.pieceStore.library.pieces.filter { piece in
            guard filter.includes(piece) else { return false }
            guard !needle.isEmpty else { return true }
            let content = piece.content
            return [content.title, content.script, content.instagramCaption, content.tiktokCaption, content.hashtags, piece.topic ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
        let byDate = Dictionary(grouping: matching, by: \.date)
        return byDate.keys.sorted(by: >).map { date in
            PieceDateGroup(date: date, pieces: services.pieceStore.pieces(on: date).filter { piece in matching.contains { $0.id == piece.id } })
        }
    }
}

struct PieceDayView: View {
    @Environment(AppServices.self) private var services
    let date: String
    @State private var composer: PieceComposerRequest?

    var body: some View {
        let pieces = services.pieceStore.pieces(on: date)
        let summary = services.pieceStore.summary(on: date)
        PieceScreen(title: PieceDates.longLabel(date)) {
            PieceLargeTitle(title: PieceDates.longLabel(date), subtitle: summary.line)
                .accessibilityIdentifier("day.title")
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                NavigationLink(value: PieceRoute.piece(piece.id)) {
                    PieceRowView(piece: piece)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day.piece.\(index)")
            }
            if summary.needsReview > 0 {
                NavigationLink(value: PieceRoute.reviewDay(date)) {
                    PieceGroup {
                        PieceInfoRow(systemImage: "checklist", title: "Review day", subtitle: "\(summary.needsReview) to review")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day.reviewDay")
            }
            PieceNote(text: "Your saved content stays editable.")
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: "Add content") {
                    composer = PieceComposerRequest(date: date)
                }
                .accessibilityIdentifier("day.addContent")
            }
        }
        .sheet(item: $composer) { request in
            PieceComposerSheet(request: request)
        }
        .task(id: date) {
            services.syncPiecesWithDayPackage(on: date)
        }
    }
}

struct PlanDayPiecesSection: View {
    @Environment(AppServices.self) private var services
    let date: String
    @State private var composer: PieceComposerRequest?

    var body: some View {
        let pieces = services.pieceStore.pieces(on: date)
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(PieceDates.longLabel(date))
                    .font(.headline)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !pieces.isEmpty {
                    NavigationLink(value: PieceRoute.planDay(date)) {
                        Text("Open day")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("plan.pieces.openDay")
                }
            }
            if !pieces.isEmpty {
                Text(services.pieceStore.summary(on: date).line)
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("plan.pieces.summary")
            }
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                NavigationLink(value: PieceRoute.piece(piece.id)) {
                    PieceRowView(piece: piece)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.pieces.piece.\(index)")
            }
            Button {
                composer = PieceComposerRequest(date: date)
            } label: {
                PieceGroup {
                    PieceInfoRow(systemImage: "plus", title: "Add content for this day") { EmptyView() }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.pieces.add")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.pieces")
        .sheet(item: $composer) { request in
            PieceComposerSheet(request: request)
        }
    }
}
