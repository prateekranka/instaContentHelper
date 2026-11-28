import Foundation

struct MiraDealFixtureService: MiraDealBriefService {
    let creatorID: UUID? = nil

    func readDealBrief(_ job: MiraDealBriefJob, start: Bool) async throws -> MiraDealBriefReply {
        let rows: [(MiraDealChecklistItem.Kind, String, String, String?)] = [
            (.shot, "Film a 30-second Reel", "Film one 30-second Reel.", nil),
            (.shot, "Share two Stories", "Share two Stories.", nil),
            (.shot, "Show the bottle", "Show the bottle in a close-up.", nil),
            (.caption, "Add the ad disclosure", "Put #ad in the caption.", "#ad"),
            (.onScreenText, "Show the discount code", "Put code SIP20 on screen.", "SIP20"),
            (.other, "Add the shop link", "Add the shop link to the second Story.", nil),
        ]
        let terms = MiraDealTerms(
            brand: "Peak Sip", fee: "₹25,000 + GST", deadline: "2026-12-08", deadlineExcerpt: "Due 8 December 2026.",
            checklist: rows.map { kind, text, excerpt, required in
                MiraDealChecklistItem(id: UUID(), kind: kind, text: text, excerpt: excerpt, requiredText: required)
            },
            disclosures: ["#ad"], codes: ["SIP20"], unresolved: ["Ask the brand for the shop link."]
        )
        let found = terms.matchesSource(job.input.briefText)
        return MiraDealBriefReply(
            id: job.id, inputRevision: MiraDealBriefJob.revision, input: job.input,
            state: found ? .succeeded : .failed, output: found ? .init(deal: terms) : nil
        )
    }
}
