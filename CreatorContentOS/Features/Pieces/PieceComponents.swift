import SwiftUI
import UIKit

enum PieceRoute: Hashable {
    case piece(UUID)
    case reviewDay(String)
    case versions(UUID)
    case version(UUID, UUID)
    case reviewChanges(UUID)
    case filming(UUID)
    case shotsReview(UUID)
    case readyToPost(UUID)
    case postOptions(UUID)
    case platformFinish(UUID, PiecePlatform)
    case postResults(UUID)
    case planDay(String)
    case yourContent
}

struct PieceRouteView: View {
    let route: PieceRoute

    var body: some View {
        switch route {
        case .piece(let id):
            PieceDetailView(pieceID: id)
        case .reviewDay(let date):
            ReviewDayView(date: date)
        case .versions(let id):
            PieceVersionsView(pieceID: id)
        case .version(let id, let versionID):
            PieceVersionPreviewView(pieceID: id, versionID: versionID)
        case .reviewChanges(let id):
            PieceReviewChangesView(pieceID: id)
        case .filming(let id):
            PieceFilmingView(pieceID: id)
        case .shotsReview(let id):
            PieceShotsReviewView(pieceID: id)
        case .readyToPost(let id):
            PieceReadyToPostView(pieceID: id)
        case .postOptions(let id):
            PiecePostOptionsView(pieceID: id)
        case .platformFinish(let id, let platform):
            PiecePlatformFinishView(pieceID: id, platform: platform)
        case .postResults(let id):
            PiecePostResultsView(pieceID: id)
        case .planDay(let date):
            PieceDayView(date: date)
        case .yourContent:
            YourContentView()
        }
    }
}

extension View {
    func pieceDestinations() -> some View {
        navigationDestination(for: PieceRoute.self) { route in
            PieceRouteView(route: route)
        }
    }
}

enum PieceDates {
    static func todayString() -> String {
        SupabaseDateFormatting.todayDateString()
    }

    static func date(from value: String) -> Date? {
        parser.date(from: String(value.prefix(10)))
    }

    static func string(from date: Date) -> String {
        parser.string(from: date)
    }

    static func localDate(from value: String) -> Date {
        guard let parsed = date(from: value) else { return Date() }
        let components = utcCalendar.dateComponents([.year, .month, .day], from: parsed)
        return Calendar.current.date(from: components) ?? Date()
    }

    static func string(fromLocal date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let utc = utcCalendar.date(from: components) else { return todayString() }
        return parser.string(from: utc)
    }

    static func shortLabel(_ value: String, today: String) -> String {
        guard let date = date(from: value) else { return value }
        let text = format("d MMM", date)
        return value == today ? "Today, \(text)" : "\(format("EEE", date)), \(text)"
    }

    static func longLabel(_ value: String) -> String {
        guard let date = date(from: value) else { return value }
        return format("EEEE, d MMMM", date)
    }

    static func compactLabel(_ value: String) -> String {
        guard let date = date(from: value) else { return value }
        return format("EEE d MMM", date)
    }

    static func adding(days: Int, to value: String) -> String {
        guard let date = date(from: value),
              let next = utcCalendar.date(byAdding: .day, value: days, to: date)
        else { return value }
        return parser.string(from: next)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static var parser: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func format(_ pattern: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct PieceScreen<Content: View, Footer: View>: View {
    var title: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                content
            }
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.top, PocketSheetSpace.xs)
            .padding(.bottom, PocketSheetSpace.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PocketSheetTheme.Color.paper, for: .navigationBar)
    }
}

struct PieceFooter<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary = { EmptyView() }
    ) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(spacing: PocketSheetSpace.xxs) {
            primary
            secondary
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.top, PocketSheetSpace.xs)
        .padding(.bottom, PocketSheetSpace.xs)
        .frame(maxWidth: .infinity)
        .background(PocketSheetTheme.Color.paper)
    }
}

struct PiecePrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSheetSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(PocketSheetType.actionPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, PocketSheetSpace.s)
            .foregroundStyle(isEnabled ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
            .background(
                isEnabled ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.hairline,
                in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
            )
        }
        .buttonStyle(PocketSheetPressFeedbackStyle())
        .disabled(!isEnabled)
    }
}

struct PieceTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PocketSheetType.actionSecondary)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PieceLargeTitle: View {
    let title: String
    var eyebrow: String?
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(PocketSheetType.sectionLabel)
                    .tracking(0.4)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PieceStatusLabel: View {
    let text: String
    let systemImage: String

    init(text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    init(piece: ContentPiece) {
        text = piece.statusLine
        systemImage = piece.stage.systemImage
    }

    var body: some View {
        HStack(spacing: PocketSheetSpace.xxs) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
    }
}

struct PieceBadge: View {
    let text: String
    let systemImage: String
    var isEmphasized = false

    var body: some View {
        HStack(spacing: PocketSheetSpace.xs) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(isEmphasized ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
        .padding(.horizontal, PocketSheetSpace.s)
        .frame(minHeight: 32)
        .background(
            isEmphasized ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.fillMuted,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

struct PieceLocalImage: View {
    let url: URL?
    var fallbackSystemImage = "photo"

    var body: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            PieceImagePlaceholder(systemImage: fallbackSystemImage)
        }
    }
}

struct PieceImagePlaceholder: View {
    let systemImage: String

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.fillMuted
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
        .accessibilityHidden(true)
    }
}

struct PieceRemoteImage: View {
    let url: URL?
    var fallbackSystemImage = "photo"

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    PieceImagePlaceholder(systemImage: fallbackSystemImage)
                }
            }
        } else {
            PieceImagePlaceholder(systemImage: fallbackSystemImage)
        }
    }
}

struct PieceThumbnail: View {
    @Environment(AppServices.self) private var services
    let piece: ContentPiece
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let fileName = localThumbnailFileName {
                PieceLocalImage(url: services.pieceStore.mediaURL(for: fileName), fallbackSystemImage: piece.content.format.systemImage)
            } else {
                PieceRemoteImage(url: piece.content.firstPreviewURL, fallbackSystemImage: piece.content.format.systemImage)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var localThumbnailFileName: String? {
        if let final = piece.finalMedia {
            return final.thumbnailFileName ?? (final.kind == .photo ? final.fileName : nil)
        }
        return piece.captures.lazy.compactMap { $0.clip?.thumbnailFileName }.first
    }
}

struct PieceRowView: View {
    let piece: ContentPiece
    var showsDate = false

    var body: some View {
        HStack(spacing: PocketSheetSpace.s) {
            PieceThumbnail(piece: piece)
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text(piece.title)
                    .font(.headline)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                PieceStatusLabel(piece: piece)
                if showsDate {
                    Text(PieceDates.compactLabel(piece.date))
                        .font(.footnote)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
            }
            Spacer(minLength: PocketSheetSpace.xs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(PocketSheetSpace.xs)
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(piece.title), \(PieceDates.longLabel(piece.date)), \(piece.statusLine)")
    }
}

struct PieceInfoRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PocketSheetSpace.s) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 28)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                if let subtitle = subtitle?.nilIfBlank {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: PocketSheetSpace.xs)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
        .contentShape(Rectangle())
    }
}

struct PieceGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct PieceNote: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PocketSheetSpace.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
    }
}

struct PieceSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PocketSheetType.sectionLabel)
            .tracking(0.4)
            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PieceMediaHero: View {
    @Environment(AppServices.self) private var services
    let piece: ContentPiece
    var height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .frame(height: height)
                    .overlay {
                        media
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
                if let duration = durationText {
                    Text(duration)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                        .padding(.horizontal, PocketSheetSpace.xs)
                        .padding(.vertical, PocketSheetSpace.xxs)
                        .background(PocketSheetTheme.Color.inverseInk.opacity(0.72), in: Capsule())
                        .padding(PocketSheetSpace.s)
                }
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption ?? "No media yet")
    }

    @ViewBuilder
    private var media: some View {
        if let final = piece.finalMedia {
            PieceLocalImage(
                url: services.pieceStore.mediaURL(for: final.thumbnailFileName ?? final.fileName),
                fallbackSystemImage: "film"
            )
        } else if let url = piece.content.firstPreviewURL {
            PieceRemoteImage(url: url, fallbackSystemImage: piece.content.format.systemImage)
        } else {
            PieceImagePlaceholder(systemImage: piece.content.format.systemImage)
        }
    }

    private var caption: String? {
        if piece.finalMedia != nil { return piece.finalMedia?.kind == .photo ? "Final photo · yours" : "Final video · yours" }
        if piece.content.firstPreviewURL != nil { return "Shot preview · generated" }
        return nil
    }

    private var durationText: String? {
        guard let seconds = piece.finalMedia?.durationSeconds else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct PieceCopyButton: View {
    let text: String
    var label = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
        } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(text.isBlankText)
    }
}
