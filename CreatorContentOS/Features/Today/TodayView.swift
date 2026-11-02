import SwiftUI

struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: TodaySheet?

    var body: some View {
        PocketSheetScreen(
            bottomContentPadding: dynamicTypeSize.isAccessibilitySize ? PocketSheetSpace.l : 120,
            showsBottomBar: !dynamicTypeSize.isAccessibilitySize
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                header
                PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
                if let decisionError = services.lastTodayDecisionSyncError?.nilIfBlank {
                    PocketSheetFeedbackBanner(
                        message: "Not saved to your account yet. \(decisionError) ContentHelper tries again each time it refreshes.",
                        kind: .issue
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.syncError")
                }
                if dynamicTypeSize.isAccessibilitySize, case .ready = services.todayContentState {
                    primaryAction
                    if services.canChooseEasierOption {
                        notEasierAction
                    }
                }
                pieceChoices
                switch services.todayContentState {
                case .ready:
                    if let package = services.todayExecutionPackageDraft() {
                        TodayInlineExecutionPackage(card: package)
                    } else {
                        TodayLoadingCard()
                    }
                case .loading:
                    TodayLoadingCard()
                case .missingPublishedCard(let date):
                    if services.todayPieces.count > 1,
                       let id = services.selectedTodayPieceID,
                       let piece = services.dayStore.piece(for: id) {
                        Text(piece.revision?.content.title ?? "Preparing your piece")
                            .font(PocketSheetType.screenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.pieceDraft.title")
                    }
                    MissingTodayCardView(date: date, isSelectedPiece: services.todayPieces.count > 1) {
                        prepareSelectedPieceInPlan()
                    }
                case .unavailable:
                    TodayUnavailableView(isRetrying: services.isRefreshingRepository) {
                        Task { await services.refreshFromRepositoriesImmediately() }
                    }
                }
            }
        } bottomBar: {
            if case .ready = services.todayContentState {
                PocketSheetCommandBar {
                    primaryAction
                    if services.canChooseEasierOption {
                        notEasierAction
                    }
                }
            }
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
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var pieceChoices: some View {
        if services.unfinishedTodayPieces.count > 1 {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("Pieces for today")
                    .font(PocketSheetType.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                ForEach(services.unfinishedTodayPieces) { piece in
                    Button {
                        services.selectTodayPiece(piece.identity.pieceID)
                    } label: {
                        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                            Text(piece.revision?.content.title ?? "Preparing your piece")
                                .font(PocketSheetType.rowTitle)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: PocketSheetSpace.xs)
                            if services.selectedTodayPieceID == piece.identity.pieceID {
                                Image(systemName: "checkmark")
                                    .font(PocketSheetType.bodyText)
                            }
                        }
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(.vertical, PocketSheetSpace.s)
                        .padding(.horizontal, PocketSheetSpace.l)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(PocketSheetTheme.Color.fillMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(services.selectedTodayPieceID == piece.identity.pieceID ? [.isSelected] : [])
                    .accessibilityIdentifier("today.piece.\(piece.position)")
                }
            }
        }
    }

    private var notEasierAction: some View {
        PocketSheetSecondaryAction(title: "Need something easier?") {
            sheet = .notToday
        }
        .accessibilityIdentifier("today.notEasier")
    }

    private var primaryActionTitle: String {
        if services.selectedTodayCard.completionState == .posted { return "View posted content" }
        if services.selectedTodayCard.isNonFilmingPost { return "Get post text" }
        if services.areAllScenesShot { return "Get post text" }
        if services.shotSceneCount > 0 { return "Continue filming" }
        return "Start filming"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Today")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.title")
                Text(todayDateLine)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("today.dateLine")
            }
            Spacer(minLength: PocketSheetSpace.s)
            if case .ready = services.todayContentState {
                readyPlanEntries
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.header")
    }

    /// Plan and narrow scene/script edit remain reachable from overflow; Shoot Folio is not the primary path.
    private var readyPlanEntries: some View {
        Menu {
            NavigationLink(value: CreatorRoute.shootFolio(editing: true)) {
                Label("Edit scenes & script", systemImage: "pencil")
            }
            .accessibilityIdentifier("today.editScenesScript")
            NavigationLink(value: CreatorRoute.plan(selectedDate: planDateForReadyCard)) {
                Label("Plan", systemImage: "calendar")
            }
            .simultaneousGesture(TapGesture().onEnded { prepareSelectedPieceInPlan() })
            if dynamicTypeSize.isAccessibilitySize && services.canChooseEasierOption {
                Button {
                    sheet = .notToday
                } label: {
                    Label("Need something easier?", systemImage: "lightbulb")
                }
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

    @ViewBuilder
    private var primaryAction: some View {
        if !services.selectedTodayCard.scenes.isEmpty || services.selectedTodayCard.isNonFilmingPost {
            NavigationLink(value: CreatorRoute.todayShootSession) {
                primaryActionLabel(
                    title: primaryActionTitle,
                    systemImage: services.selectedTodayCard.isNonFilmingPost ? "text.bubble" : "video.fill"
                )
            }
            .buttonStyle(PocketSheetPressFeedbackStyle())
            .accessibilityLabel(primaryActionTitle)
            .accessibilityIdentifier("today.startFilming")
        } else {
            NavigationLink(value: CreatorRoute.shootFolio(editing: false)) {
                primaryActionLabel(title: "Open shoot plan", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(PocketSheetPressFeedbackStyle())
            .accessibilityIdentifier("today.openShootPlan")
        }
    }

    private func primaryActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: PocketSheetSpace.xs) {
            Image(systemName: systemImage)
            Text(title)
                .font(PocketSheetType.actionPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .foregroundStyle(PocketSheetTheme.Color.inversePaper)
        .background(PocketSheetTheme.Color.inverseInk)
        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
    }

    private func prepareSelectedPieceInPlan() {
        let date = services.currentTodayDateString
        appState.preparePlan(selecting: date)
        if let pieceID = services.selectedTodayPieceID {
            appState.selectPlanPiece(pieceID, on: date, context: services.context)
        }
    }

    private var planDateForReadyCard: String {
        services.selectedTodayCard.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
    }

    private var todayDateLine: String {
        if case .missingPublishedCard(let date) = services.todayContentState {
            return Self.formattedHeadingDate(from: date) ?? date
        }

        let todayDateString = services.currentTodayDateString
        guard let scheduledDate = services.selectedTodayCard.scheduledDate,
              let date = Self.apiDateFormatter.date(from: scheduledDate),
              !SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDateString)
        else {
            return Self.formattedHeadingDate(from: todayDateString) ?? todayDateString
        }

        return Self.headingDateString(from: date)
    }

    private static func formattedHeadingDate(from apiDate: String) -> String? {
        guard let date = apiDateFormatter.date(from: apiDate) else { return nil }
        return headingDateString(from: date)
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let headingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static func headingDateString(from date: Date) -> String {
        let day = Calendar(identifier: .gregorian).component(.day, from: date)
        return headingDateFormatter.string(from: date)
            .replacingOccurrences(of: "\(day) ", with: "\(ordinalDay(day)) ", options: .anchored)
    }

    private static func ordinalDay(_ day: Int) -> String {
        let suffix: String
        switch day {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1:
                suffix = "st"
            case 2:
                suffix = "nd"
            case 3:
                suffix = "rd"
            default:
                suffix = "th"
            }
        }
        return "\(day)\(suffix)"
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
                Text("Getting your latest card…")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.loading")
    }
}

private struct TodayUnavailableView: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Can't load today")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text("Check your connection, then try again.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                PocketSheetPrimaryAction(title: isRetrying ? "Trying again" : "Try again", action: onRetry)
                    .disabled(isRetrying)
                    .accessibilityIdentifier("today.retryLoad")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MissingTodayCardView: View {
    let date: String
    var isSelectedPiece = false
    let onPlan: () -> Void

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text(isSelectedPiece ? "This piece needs review" : "Nothing ready for today")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(isSelectedPiece ? "Open this piece in Plan and make it ready before filming." : "There’s no ready package for this date yet. Open Plan to generate one and make it available on Today.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .lineSpacing(4)
                }

                NavigationLink(value: CreatorRoute.plan(selectedDate: date)) {
                    HStack(spacing: PocketSheetSpace.s) {
                        Image(systemName: "calendar.badge.plus")
                        Text("Plan today’s content")
                    }
                    .font(PocketSheetType.actionPrimary)
                    .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        PocketSheetTheme.Color.inverseInk,
                        in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded(onPlan))
                .accessibilityLabel("Plan today’s content")
                .accessibilityIdentifier("today.planCTA")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.emptyCard")
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
