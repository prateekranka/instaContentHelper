import Foundation

/// Persists the Creator Plan calendar selection (`yyyy-MM-dd`) across tab changes and relaunch.
protocol PlanSelectedDateStoring: Sendable {
    func load() -> String?
    func save(_ scheduledDate: String?)
    func clear()
    func loadPiece(for key: String) -> UUID?
    func savePiece(_ pieceID: UUID, for key: String)
}

extension PlanSelectedDateStoring {
    func loadPiece(for key: String) -> UUID? { nil }
    func savePiece(_ pieceID: UUID, for key: String) {}
}

struct UserDefaultsPlanSelectedDateStore: PlanSelectedDateStoring, @unchecked Sendable {
    static let shared = UserDefaultsPlanSelectedDateStore()

    private let defaults: UserDefaults
    private let key = "ch-plan-selected-date"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> String? {
        defaults.string(forKey: key)?.nilIfBlank
    }

    func save(_ scheduledDate: String?) {
        guard let scheduledDate = scheduledDate?.nilIfBlank else {
            clear()
            return
        }
        defaults.set(scheduledDate, forKey: key)
    }

    func loadPiece(for key: String) -> UUID? {
        defaults.string(forKey: "ch-plan-selected-piece." + key).flatMap(UUID.init(uuidString:))
    }

    func savePiece(_ pieceID: UUID, for key: String) {
        defaults.set(pieceID.uuidString, forKey: "ch-plan-selected-piece." + key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
