import Foundation

struct MiraContinueReel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let progress: MiraReelProgress

    var completedSteps: Int {
        switch progress {
        case .choosing: 0
        case .writing, .approving: 1
        case .planning, .ready: 2
        case .filming: 3
        case .complete: 4
        }
    }

    var nextAction: MiraNextAction {
        progress.nextAction
    }
}

enum MiraHomeFeedEvent {
    case workChanged([MiraProject], resume: UUID?)
}

enum MiraHomeFeed {
    case empty
    case continuing([MiraContinueReel])

    func handle(_ event: MiraHomeFeedEvent) -> Self {
        switch event {
        case .workChanged(let projects, let resume):
            let openReels = projects.sorted { $0.updatedAt > $1.updatedAt }.compactMap { project -> MiraContinueReel? in
                let progress = project.stage
                guard !project.archived, progress != .complete,
                    !project.ideas.isEmpty || !project.scripts.isEmpty || project.hasWorkingCards
                        || project.todayCards?.contains(where: { $0.output != nil }) == true
                else { return nil }
                return MiraContinueReel(id: project.id, title: project.idea?.title ?? project.title, progress: progress)
            }
            guard !openReels.isEmpty else { return .empty }
            if let reel = openReels.first(where: { $0.id == resume }) {
                return .continuing([reel] + openReels.filter { $0.id != reel.id })
            }
            return .continuing(openReels)
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .empty: .makeToday
        case .continuing(let reels): reels.first?.nextAction ?? .continueWork
        }
    }

    func contains(_ id: UUID) -> Bool {
        guard case .continuing(let reels) = self else { return false }
        return reels.contains { $0.id == id }
    }
}
