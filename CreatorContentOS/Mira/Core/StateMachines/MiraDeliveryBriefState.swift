import Foundation

enum MiraDeliveryBriefEvent {
    case start(UUID, MiraDeliveryJob<MiraBriefCheckInput>)
    case received(UUID, [MiraBriefCheck])
    case interrupted(UUID, String)
    case rejected(UUID, String)
    case apply(UUID, MiraBriefCheckInput)
}

enum MiraDeliveryBriefState {
    case unchecked
    case checking(MiraDeliveryReview)
    case interrupted(MiraDeliveryReview)
    case rejected(MiraDeliveryReview)
    case reviewed(MiraDeliveryReview)

    init(review: MiraDeliveryReview?, running: Bool) {
        guard let review else { self = .unchecked; return }
        if running { self = .checking(review) }
        else if review.checks != nil { self = .reviewed(review) }
        else if review.job.creatorID == nil && review.issue != nil { self = .rejected(review) }
        else { self = .interrupted(review) }
    }

    var record: MiraDeliveryReview? {
        switch self {
        case .unchecked: nil
        case .checking(let review), .interrupted(let review), .rejected(let review), .reviewed(let review): review
        }
    }

    func handle(_ event: MiraDeliveryBriefEvent) -> Self? {
        switch (self, event) {
        case (.unchecked, .start(let deal, let job)), (.rejected, .start(let deal, let job)),
             (.reviewed, .start(let deal, let job)):
            return .checking(MiraDeliveryReview(dealID: deal, job: job))
        case (.interrupted(var review), .start(let deal, let job)) where review.dealID == deal && review.job == job:
            review.issue = nil
            return .checking(review)
        case (.checking(var review), .received(let id, let checks)) where review.job.id == id:
            let checklist = review.job.input.checklist
            guard checklist.count == checks.count, Set(checks.map(\.id)) == Set(checklist.map(\.id)) else { return nil }
            review.checks = checklist.compactMap { item in
                checks.first(where: { $0.id == item.id })?.validated(for: item, input: review.job.input)
            }
            return .reviewed(review)
        case (.checking(var review), .interrupted(let id, let issue)) where review.job.id == id:
            review.issue = issue
            return .interrupted(review)
        case (.checking(let review), .rejected(let id, let issue)) where review.job.id == id:
            let job = MiraDeliveryJob(id: id, creatorID: nil, input: review.job.input)
            return .rejected(MiraDeliveryReview(dealID: review.dealID, job: job, issue: issue))
        case (.reviewed(let review), .apply(let id, let input)):
            guard let checks = review.checks, let check = checks.first(where: { $0.id == id }),
                let fix = check.fix, let text = fix.text, check.status == .canFix else { return nil }
            let actual = fix.field == .caption ? input.caption : input.onScreenText
            guard actual.contains(text) else { return nil }
            let updated = checks.map {
                $0.id == id ? MiraBriefCheck(itemID: id, status: .met, evidence: .init(
                    field: fix.field, excerpt: text, text: nil)) : $0
            }
            return .reviewed(MiraDeliveryReview(dealID: review.dealID,
                job: MiraDeliveryJob(id: review.job.id, creatorID: review.job.creatorID, input: input),
                checks: updated))
        default:
            return nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .unchecked: .checkReelBrief
        case .checking: .wait
        case .interrupted: .reconnect
        case .rejected: .retry
        case .reviewed: .shareReel
        }
    }
}
