import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var activeMode: AppMode
    var runtime: AppRuntime

    init(activeMode: AppMode = .mamta, runtime: AppRuntime? = nil) {
        self.activeMode = activeMode
        self.runtime = runtime ?? AppRuntime.makeInitialRuntime()
    }

    func replaceRuntime(_ runtime: AppRuntime) {
        self.runtime = runtime
    }
}

enum AppMode: String, CaseIterable, Codable, Hashable {
    case mamta
    case admin
}
