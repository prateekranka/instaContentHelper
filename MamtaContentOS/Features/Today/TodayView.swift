import SwiftUI

struct TodayView: View {
    @Environment(AppServices.self) private var services
    @State private var sheet: TodaySheet?

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                TodayHeroCard(card: services.todayCard)

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
                NavigationLink(value: MamtaRoute.shootFolio) {
                    Text("See what to shoot")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(MCOTheme.Color.paperRaised)
                        .background(MCOTheme.Color.oxblood)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                SecondaryActionButton(title: "Not today") {
                    sheet = .notToday
                }
                .frame(maxWidth: 140)
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
                Text("MC")
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text("Today")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(services.todayCard.context)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
            }
            Spacer()
            FloatingIconButton(systemImage: "gearshape", label: "Settings") {}
                .padding(.top, MCOSpace.l)
        }
    }
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
                Rectangle()
                    .fill(MCOTheme.Color.brass)
                    .frame(width: 44, height: 1)
                Text(card.whyToday)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MCOSpace.xl)
                Spacer()
            }
            .padding(MCOSpace.l)
        }
        .frame(minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        TodayView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
