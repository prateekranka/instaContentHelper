import SwiftUI

struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @State private var sheet: TodaySheet?

    var body: some View {
        PocketSheetScreen(bottomContentPadding: 120) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                header
                PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
                if let decisionError = services.lastTodayDecisionSyncError?.nilIfBlank {
                    PocketSheetFeedbackBanner(
                        message: "Couldn't save your decision — \(decisionError)",
                        kind: .issue
                    )
                }
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
                    MissingTodayCardView(date: date) {
                        appState.preparePlan(selecting: date)
                    }
                }
            }
        } bottomBar: {
            if case .ready = services.todayContentState {
                PocketSheetCommandBar {
                    if services.canMarkPosted {
                        PocketSheetPrimaryAction(
                            title: "Mark as posted",
                            systemImage: "paperplane.fill"
                        ) {
                            services.markPosted()
                        }
                        .accessibilityIdentifier("today.markPosted")
                    } else if !services.todayCard.scenes.isEmpty {
                        PocketSheetPrimaryAction(
                            title: services.areAllScenesShot ? "All scenes shot" : "Mark all as shot",
                            systemImage: services.areAllScenesShot ? "checkmark.circle.fill" : "checkmark.seal"
                        ) {
                            services.markAllScenesShot()
                        }
                        .disabled(services.areAllScenesShot)
                        .accessibilityIdentifier("today.markAllScenesShot")
                    }

                    PocketSheetSecondaryAction(title: "Give me other ideas") {
                        sheet = .notToday
                    }
                    .accessibilityIdentifier("today.notEasier")
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .notToday:
                NotTodaySheet()
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
            }
        }
        .navigationBarHidden(true)
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 42, height: 42)
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

    private var planDateForReadyCard: String {
        services.todayCard.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
    }

    private var todayDateLine: String {
        if case .missingPublishedCard(let date) = services.todayContentState {
            return Self.formattedHeadingDate(from: date) ?? date
        }

        let todayDateString = services.currentTodayDateString
        guard let scheduledDate = services.todayCard.scheduledDate,
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

private struct MissingTodayCardView: View {
    let date: String
    let onPlan: () -> Void

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Nothing ready for today")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text("There’s no ready package for this date yet. Open Plan to generate one and make it available on Today.")
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
