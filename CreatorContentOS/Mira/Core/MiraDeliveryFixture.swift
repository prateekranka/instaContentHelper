#if DEBUG
import Foundation

struct MiraDeliveryFixture: MiraDeliveryService {
    let creatorID: UUID? = nil

    func briefCheck(_ job: MiraDeliveryJob<MiraBriefCheckInput>, start: Bool) async throws
        -> MiraDeliveryReply<MiraBriefCheckInput, MiraBriefCheckOutput> {
        let checks = job.input.checklist.map { item -> MiraBriefCheck in
            if item.kind == .onScreenText, let code = item.requiredText, !job.input.onScreenText.contains(code) {
                return MiraBriefCheck(itemID: item.id, status: .canFix,
                    fix: .init(field: .onScreenText, excerpt: nil, text: "Use code \(code)"))
            }
            if item.kind == .caption, let tag = item.requiredText, job.input.caption.contains(tag) {
                return MiraBriefCheck(itemID: item.id, status: .met,
                    evidence: .init(field: .caption, excerpt: tag, text: nil))
            }
            return MiraBriefCheck(itemID: item.id, status: .missing)
        }
        return .init(id: job.id, inputRevision: job.revision, input: job.input,
            state: .succeeded, output: .init(checks: checks))
    }

    func brandNote(_ job: MiraDeliveryJob<MiraBrandNoteInput>, start: Bool) async throws
        -> MiraDeliveryReply<MiraBrandNoteInput, MiraBrandNoteOutput> {
        .init(id: job.id, inputRevision: job.revision, input: job.input,
            state: .succeeded, output: .init(message: "Hi \(job.input.brand), I posted the Reel. Thanks for working with me!"))
    }

    static func sampleDocument() -> MiraDocument {
        let requirements = [
            MiraDealChecklistItem(id: UUID(), kind: .caption, text: "Add the ad disclosure",
                excerpt: "Put #ad in the caption.", requiredText: "#ad"),
            MiraDealChecklistItem(id: UUID(), kind: .onScreenText, text: "Show the discount code",
                excerpt: "Show discount code SIP20 on screen.", requiredText: "SIP20"),
            MiraDealChecklistItem(id: UUID(), kind: .shot, text: "Show the bottle",
                excerpt: "Show the bottle in a close-up.", requiredText: nil),
        ]
        let terms = MiraDealTerms(brand: "Peak Sip", fee: "", deadline: "", deadlineExcerpt: "",
            checklist: requirements, disclosures: ["#ad"], codes: ["SIP20"], unresolved: [])
        let deal = MiraDeal(id: UUID(), source: requirements.map(\.excerpt).joined(separator: "\n"),
            terms: terms, confirmedAt: Date())

        let idea = MiraIdea(title: "Sample delivery Reel", hook: "Start with a sip", visual: "Pour water",
            fit: "", filmingMinutes: 10, setup: "")
        let script = MiraScript(hook: idea.hook, spoken: "", caption: "A small reset #ad.",
            durationSeconds: 15, language: "English")
        let shots = [4, 5, 6].enumerated().map { index, duration in
            MiraShot(purpose: ["Show the glass", "Pour water", "Take a sip"][index],
                editedSeconds: duration, recordingSeconds: duration, location: "Kitchen", props: "Glass",
                placement: "At eye level", action: "Film the glass", words: index == 0 ? script.hook : "", voiceover: false,
                onScreenText: "", simplerAlternative: "")
        }
        let board = MiraStoryboard(sourceScriptID: script.id, requirementsRevision: 0, shots: shots, mappings: [])
        var project = MiraProject()
        project.title = idea.title
        project.ideas = [idea]
        project.selectedIdeaID = idea.id
        project.scripts = [script]
        project.activeScriptID = script.id
        project.approvedScriptID = script.id
        project.storyboards = [board]
        project.activeStoryboardID = board.id
        project.startedFilming = true
        project.filmed = shots.map(\.id)
        project.dealID = deal.id
        project.isDemo = true
        var document = MiraDocument()
        document.projects = [project]
        document.deals = [deal]
        return document
    }
}
#endif
