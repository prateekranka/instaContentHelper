import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var sheet: TodaySheet?
    let onOpenProfile: () -> Void

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                switch services.todayContentState {
                case .ready:
                    NavigationLink(value: CreatorRoute.shootFolio) {
                        TodayHeroCard(card: services.todayCard)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open today's Shoot Folio")
                case .loading:
                    TodayLoadingCard()
                case .missingPublishedCard(let date):
                    MissingTodayCardView(
                        date: date,
                        canOpenWeekly: canOpenManagerWeekly,
                        onOpenWeekly: openManagerWeekly,
                        onOpenProfile: onOpenProfile
                    )
                }

                if case .ready = services.todayContentState,
                   let completion = services.todayCard.completionState {
                    JournalBlock {
                        HStack {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(MCOTheme.Color.sageDeep)
                            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                                Text("Decision made")
                                    .font(MCOType.headline)
                                Text(completion.archiveLabel)
                                    .font(MCOType.bodySmall)
                                    .foregroundStyle(MCOTheme.Color.inkMuted)
                            }
                        }
                    }
                }
            }
        } bottomBar: {
            if case .ready = services.todayContentState {
                GlassCommandBar {
                    SecondaryActionButton(title: "Give me other ideas") {
                        sheet = .notToday
                    }
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
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Today")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(todayDateLine)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
            }
            Spacer()
            FloatingIconButton(systemImage: "person.crop.circle", label: "Open Profile") {
                onOpenProfile()
            }
        }
    }

    private var canOpenManagerWeekly: Bool {
        services.memberRole == "owner" || services.memberRole == "editor"
    }

    private func openManagerWeekly() {
        appState.activeMode = .admin
    }

    private var todayDateLine: String {
        if case .missingPublishedCard(let date) = services.todayContentState {
            return Self.formattedHeadingDate(from: date) ?? date
        }

        guard let scheduledDate = services.todayCard.scheduledDate,
              let date = Self.apiDateFormatter.date(from: scheduledDate)
        else {
            return services.todayCard.context
        }

        return Self.headingDateFormatter.string(from: date)
    }

    private static func formattedHeadingDate(from apiDate: String) -> String? {
        guard let date = apiDateFormatter.date(from: apiDate) else { return nil }
        return headingDateFormatter.string(from: date)
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
        formatter.dateFormat = "EEEE, dd/MM/yy"
        return formatter
    }()
}

private struct TodayLoadingCard: View {
    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                ProgressView()
                Text("Checking today's plan")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("The app is loading the latest published card.")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MissingTodayCardView: View {
    let date: String
    let canOpenWeekly: Bool
    let onOpenWeekly: () -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(MCOTheme.Color.brass)
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    Text("Nothing scheduled for today")
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(message)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineSpacing(4)
                }

                if canOpenWeekly {
                    PrimaryActionButton(title: "Open Weekly", systemImage: "calendar") {
                        onOpenWeekly()
                    }
                } else {
                    SecondaryActionButton(title: "Open Profile") {
                        onOpenProfile()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var message: String {
        if canOpenWeekly {
            return "There is no published plan for \(date). Open Weekly, publish the right day, then return here."
        }
        return "Your manager has not published a plan for \(date) yet. Check back after the week is ready."
    }
}

struct TodayHeroCard: View {
    let card: DailyCard

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x17130F),
                            Color(hex: 0x4A3829),
                            Color(hex: 0x17130F)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            GeometryReader { proxy in
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(.white.opacity(0.06))
                    .rotationEffect(.degrees(-18))
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.28)
            }
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .center) {
                    Text(card.effortLabel)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.paperRaised)
                        .padding(.horizontal, MCOSpace.s)
                        .padding(.vertical, 7)
                        .background(MCOTheme.Color.sageDeep.opacity(0.78), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(MCOTheme.Color.paperRaised.opacity(0.28), lineWidth: 1)
                        }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.7))
                }

                Text(card.title)
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)

                Text(card.whyToday)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                if !scenePreviewLines.isEmpty {
                    VStack(alignment: .leading, spacing: MCOSpace.xs) {
                        ForEach(scenePreviewLines, id: \.self) { sceneLine in
                            HStack(spacing: MCOSpace.xs) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(sceneLine)
                                    .font(MCOType.caption)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.74))
                        }
                    }
                    .padding(.top, MCOSpace.xs)
                }

                Spacer(minLength: 0)

                HStack(spacing: MCOSpace.xs) {
                    Text("Open Shoot Folio")
                        .font(MCOType.caption)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.82))
            }
            .padding(MCOSpace.l)
        }
        .frame(minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var scenePreviewLines: [String] {
        card.scenes.prefix(2).map { scene in
            "\(scene.number). \(scene.title)"
        }
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
