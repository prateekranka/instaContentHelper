import Foundation

enum MiraReelPostEvent {
    case shared(Date)
    case confirm(Date, dealID: UUID?, exportID: UUID)
    case verified(URL)
}

enum MiraReelPostState {
    case ready
    case shared(Date)
    case posted(MiraPostedReel)
    case live(MiraPostedReel)

    init(record: MiraDelivery) {
        if let post = record.post { self = post.link == nil ? .posted(post) : .live(post) }
        else if let date = record.sharedAt { self = .shared(date) }
        else { self = .ready }
    }

    func handle(_ event: MiraReelPostEvent) -> Self? {
        switch (self, event) {
        case (.ready, .shared(let date)), (.shared, .shared(let date)):
            return .shared(date)
        case (.shared(let sharedAt), .confirm(let date, let dealID, let exportID)) where sharedAt <= date:
            return .posted(MiraPostedReel(date: date, dealID: dealID, exportID: exportID, link: nil))
        case (.posted(let post), .verified(let link)) where link.scheme == "https"
            && ["instagram.com", "www.instagram.com"].contains(link.host ?? "")
            && (link.path.hasPrefix("/reel/") || link.path.hasPrefix("/p/")):
            return .live(MiraPostedReel(date: post.date, dealID: post.dealID, exportID: post.exportID, link: link))
        default:
            return nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .ready: .shareReel
        case .shared: .confirmReelPost
        case .posted(let post), .live(let post): post.dealID == nil ? .previewReel : .writeBrandNote
        }
    }
}
