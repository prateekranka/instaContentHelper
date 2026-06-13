import SwiftUI

struct TodayView: View {
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
                NavigationLink(value: CreatorRoute.shootFolio) {
                    TodayHeroCard(card: services.todayCard)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open today's Shoot Folio")

                if let completion = services.todayCard.completionState {
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
            GlassCommandBar {
                SecondaryActionButton(title: "Give me other ideas") {
                    sheet = .notToday
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
            FloatingIconButton(systemImage: "gearshape", label: "Open Profile") {
                onOpenProfile()
            }
        }
    }

    private var todayDateLine: String {
        guard let scheduledDate = services.todayCard.scheduledDate,
              let date = Self.apiDateFormatter.date(from: scheduledDate)
        else {
            return services.todayCard.context
        }

        return Self.headingDateFormatter.string(from: date)
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

struct TodayHeroCard: View {
    let card: DailyCard

    var body: some View {
        ZStack {
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
                    .font(.system(size: 112, weight: .light))
                    .foregroundStyle(.white.opacity(0.09))
                    .rotationEffect(.degrees(-18))
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.28)
                Image(systemName: "book.closed")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(.white.opacity(0.08))
                    .rotationEffect(.degrees(12))
                    .position(x: proxy.size.width * 0.28, y: proxy.size.height * 0.78)
            }
            VStack(spacing: MCOSpace.l) {
                Spacer()
                Text(card.title)
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Text(cardSubtitle)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.paperRaised.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, MCOSpace.m)
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
            }
            .padding(MCOSpace.l)
        }
        .frame(minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cardSubtitle: String {
        card.sourceNote?.nilIfBlank ?? card.context
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
