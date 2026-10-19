import SwiftUI

struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: TodaySheet?
    @State private var composer: PieceComposerRequest?

    var body: some View {
        PieceScreen {
            header
            PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
            if let decisionError = services.lastTodayDecisionSyncError?.nilIfBlank {
                PocketSheetFeedbackBanner(
                    message: "Couldn't save your decision — \(decisionError)",
                    kind: .issue
                )
            }
            if let storeError = services.pieceStore.lastError?.nilIfBlank {
                PocketSheetFeedbackBanner(message: storeError, kind: .issue)
            }
            if case .failed = services.pieceStore.syncStatus, services.pieceStore.hasUnsyncedChanges {
                PocketSheetFeedbackBanner(
                    message: "Offline · saved on this device. Changes sync when you reconnect.",
                    kind: .pending
                )
                .accessibilityIdentifier("today.syncPending")
            }
            if pieces.isEmpty {
                if case .loading = services.todayContentState {
                    TodayLoadingCard()
                } else {
                    emptyDay
                }
            } else {
                piecesList
            }
        } footer: {
            footer
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: syncKey) {
            services.syncPiecesWithDayPackages()
            await services.pieceStore.syncNow()
        }
        .refreshable {
            await services.pieceStore.syncNow()
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .notToday:
                NotTodaySheet()
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $composer) { request in
            PieceComposerSheet(request: request)
        }
    }

    private var today: String { services.currentTodayDateString }

    private var pieces: [ContentPiece] { services.pieceStore.pieces(on: today) }

    private var summary: PieceDaySummary { services.pieceStore.summary(on: today) }

    private var syncKey: String {
        "\(services.todayCard.id.uuidString)-\(services.todayCard.completionState?.rawValue ?? "")-\(services.dayBriefGeneratedCards.count)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.title")
                Spacer(minLength: PocketSheetSpace.s)
                Button {
                    appState.preparePlan(selecting: today)
                    appState.requestCreatorTab(.plan)
                } label: {
                    Label(PieceDates.compactLabel(today), systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(PieceDates.longLabel(today)) in Plan")
                .accessibilityIdentifier("today.dateLine")
                optionsMenu
            }
            if !pieces.isEmpty {
                Text(summary.line)
                    .font(.subheadline)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("today.summary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.header")
    }

    private var optionsMenu: some View {
        Menu {
            if !pieces.isEmpty {
                NavigationLink(value: PieceRoute.reviewDay(today)) {
                    Label(summary.needsReview > 0 ? "Review day · \(summary.needsReview) to review" : "Review day", systemImage: "checklist")
                }
                .accessibilityIdentifier("today.reviewDay")
            }
            Button {
                composer = PieceComposerRequest(date: today)
            } label: {
                Label("Add content", systemImage: "plus")
            }
            if hasLegacyTodayPackage {
                Button {
                    sheet = .notToday
                } label: {
                    Label("Need something easier?", systemImage: "lightbulb")
                }
                .accessibilityIdentifier("today.notEasier")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .background(PocketSheetTheme.Color.paperRaised, in: Circle())
                .overlay {
                    Circle().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Today options")
        .accessibilityIdentifier("today.overflow")
    }

    private var hasLegacyTodayPackage: Bool {
        guard case .ready = services.todayContentState else { return false }
        return pieces.contains { $0.linkedDailyCardID == services.todayCard.id }
    }

    private var piecesList: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            if summary.total > 0, summary.needsReview == 0, summary.approved == summary.total {
                HStack(spacing: PocketSheetSpace.s) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(summary.line)
                        .font(.body.weight(.medium))
                }
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PocketSheetSpace.m)
                .background(PocketSheetTheme.Color.fillMuted, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.dayApproved")
            }
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                NavigationLink(value: PieceRoute.piece(piece.id)) {
                    PieceRowView(piece: piece)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.piece.\(index)")
            }
            Button {
                composer = PieceComposerRequest(date: today)
            } label: {
                HStack(spacing: PocketSheetSpace.s) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                    Text("Add content")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .frame(minHeight: 52)
                .padding(.horizontal, PocketSheetSpace.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.addContent")
            Text("New content can be added at any time.")
                .font(.footnote)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private var emptyDay: some View {
        VStack(spacing: PocketSheetSpace.m) {
            Image(systemName: "doc.text")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .padding(.top, PocketSheetSpace.xl)
                .accessibilityHidden(true)
            Text("Your day starts here")
                .font(.title2.weight(.bold))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .multilineTextAlignment(.center)
            Text("Create a draft, then approve it when you are ready.")
                .font(.body)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.empty")
    }

    @ViewBuilder
    private var footer: some View {
        if pieces.isEmpty {
            if case .loading = services.todayContentState {
                EmptyView()
            } else {
                PieceFooter {
                    PiecePrimaryButton(title: "Create first draft") {
                        composer = PieceComposerRequest(date: today)
                    }
                    .accessibilityIdentifier("today.empty.create")
                } secondary: {
                    PieceTextButton(title: "Write it myself") {
                        composer = PieceComposerRequest(date: today, startsManual: true)
                    }
                    .accessibilityIdentifier("today.empty.write")
                }
            }
        } else if let next = nextAction {
            PieceFooter {
                NavigationLink(value: next.route) {
                    TodayPrimaryLabel(title: next.title)
                }
                .buttonStyle(PocketSheetPressFeedbackStyle())
                .accessibilityIdentifier("today.primaryAction")
            }
        }
    }

    private var nextAction: (title: String, route: PieceRoute)? {
        if let filming = pieces.first(where: { $0.isFilmingInProgress && $0.content.format.usesFilming && !$0.filmingShots.isEmpty }) {
            return ("Continue filming", .filming(filming.id))
        }
        let drafts = pieces.filter(\.needsReview)
        if drafts.count == 1, let draft = drafts.first {
            return ("Review draft", .piece(draft.id))
        }
        if drafts.count > 1 {
            return ("Review day", .reviewDay(today))
        }
        if let toFilm = pieces.first(where: { $0.stage == .approved && $0.content.format.usesFilming && !$0.filmingShots.isEmpty }) {
            return ("Start filming", .filming(toFilm.id))
        }
        if let toPrepare = pieces.first(where: { $0.stage == .approved }) {
            return ("Prepare media", .readyToPost(toPrepare.id))
        }
        if let toPost = pieces.first(where: { $0.stage == .shot }) {
            return ("Prepare to post", .readyToPost(toPost.id))
        }
        return nil
    }
}

private struct TodayPrimaryLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PocketSheetType.actionPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
            .background(
                PocketSheetTheme.Color.inverseInk,
                in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
            )
    }
}

private struct TodayLoadingCard: View {
    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                ProgressView()
                    .tint(PocketSheetTheme.Color.ink)
                Text("Checking today's plan")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Getting your latest content…")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.loading")
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
