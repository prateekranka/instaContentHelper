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
                if let repositoryError = services.lastRepositoryError?.nilIfBlank {
                    ActionFeedbackBanner(message: "Couldn't save your decision — \(repositoryError)", tone: .danger)
                }
                switch services.todayContentState {
                case .ready:
                    NavigationLink(value: CreatorRoute.shootFolio) {
                        TodayHeroCard(card: services.todayCard)
                    }
                    .buttonStyle(.pressable(scale: 0.985))
                    .accessibilityLabel("Open today's Shoot Folio")
                case .loading:
                    TodayLoadingCard()
                case .missingPublishedCard(let date):
                    MissingTodayCardView(
                        date: date,
                        canOpenDaily: canOpenManagerDaily,
                        onOpenDaily: openManagerDaily,
                        onOpenProfile: onOpenProfile
                    )
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
                    .presentationDetents([.height(560), .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Today")
                    .font(MCOType.display)
                    .tracking(MCOType.displayTracking)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(todayDateLine)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
            }
            Spacer()
        }
    }

    private var canOpenManagerDaily: Bool {
        services.memberRole == "owner" || services.memberRole == "editor"
    }

    private func openManagerDaily() {
        appState.activeMode = .admin
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
    @State private var shimmerPhase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                ProgressView()
                    .controlSize(.regular)
                Text("Checking today's plan")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("The app is loading the latest published card.")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)

                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    skeletonBar(widthFraction: 0.72)
                    skeletonBar(widthFraction: 0.9)
                    skeletonBar(widthFraction: 0.54)
                }
                .padding(.top, MCOSpace.xs)
                .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }

    private func skeletonBar(widthFraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MCOTheme.Color.hairline.opacity(0.55))
                .frame(width: proxy.size.width * widthFraction, height: 10)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [
                                .clear,
                                MCOTheme.Color.paperRaised.opacity(0.55),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: (shimmerPhase * 2 - 1) * proxy.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 10)
    }
}

private struct MissingTodayCardView: View {
    let date: String
    let canOpenDaily: Bool
    let onOpenDaily: () -> Void
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

                if canOpenDaily {
                    PrimaryActionButton(title: "Open Daily", systemImage: "calendar.badge.plus") {
                        onOpenDaily()
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
        if canOpenDaily {
            return "There is no published card for \(date). Open Daily, choose the date, and publish that card."
        }
        return "Your manager has not published a card for \(date) yet. Check back after that day is ready."
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
                    Text("See what to shoot")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.72))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.7))
                }

                Text(card.title)
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .tracking(-0.4)
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)

                if let whyLine = glanceSupportingLine {
                    Text(whyLine)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(MCOSpace.l)
        }
        .frame(minHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
    }

    /// Glance density: one supporting sentence. Prefer why-today; fall back to hook.
    private var glanceSupportingLine: String? {
        card.whyToday.nilIfBlank ?? card.effectiveHook?.nilIfBlank
    }
}

extension DailyCard {
    /// The hook shown on the Today card. Prefers the generated `hook` (the
    /// answer to "what are we enticing people to stop for?"). When the source
    /// card has no hook, derive a fallback from the richest available copy so
    /// the card stays useful without simply repeating the title.
    var effectiveHook: String? {
        if let hook { return hook }
        return caption?.nilIfBlank
            ?? script?.nilIfBlank
            ?? title.nilIfBlank
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
