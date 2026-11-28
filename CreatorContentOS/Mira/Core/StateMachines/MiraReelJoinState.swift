import Foundation

enum MiraReelJoinEvent {
    case build(UUID, MiraRenderRecipe)
    case rendered(UUID, MiraReelExport)
    case failed(UUID, String)
}

enum MiraReelJoinState {
    case needsClips
    case ready(MiraRenderRecipe)
    case rendering(UUID, MiraRenderRecipe)
    case failed(MiraRenderRecipe, String)
    case finished(MiraReelExport)

    func handle(_ event: MiraReelJoinEvent) -> Self? {
        switch (self, event) {
        case (.ready(let current), .build(let id, let recipe)) where current == recipe,
             (.failed(let current, _), .build(let id, let recipe)) where current == recipe:
            return .rendering(id, recipe)
        case (.rendering(let current, let recipe), .rendered(let id, let output))
            where current == id && recipe == output.recipe:
            return .finished(output)
        case (.rendering(let current, let recipe), .failed(let id, let issue)) where current == id:
            return .failed(recipe, issue)
        default:
            return nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .needsClips: .prepareClips
        case .ready: .joinReel
        case .rendering: .wait
        case .failed: .retry
        case .finished: .previewReel
        }
    }
}
