import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var activeMode: AppMode

    init(activeMode: AppMode = .mamta) {
        self.activeMode = activeMode
    }
}

enum AppMode: String, CaseIterable, Codable, Hashable {
    case mamta
    case admin
}
