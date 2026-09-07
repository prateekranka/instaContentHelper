import Foundation

/// One accepted async day-generation run that must be resumed via status polling — never re-POSTed.
struct AcceptedDayGenerationRun: Codable, Hashable, Sendable {
    var scheduledDate: String
    var generationID: UUID
    var creatorID: UUID
    var acceptedAt: Date
}

protocol AcceptedDayGenerationStoring: Sendable {
    func loadAll() -> [AcceptedDayGenerationRun]
    func load(scheduledDate: String) -> AcceptedDayGenerationRun?
    func save(_ run: AcceptedDayGenerationRun)
    func remove(scheduledDate: String)
    func clear()
}

struct UserDefaultsAcceptedDayGenerationStore: AcceptedDayGenerationStoring, @unchecked Sendable {
    static let shared = UserDefaultsAcceptedDayGenerationStore()

    private let defaults: UserDefaults
    private let key = "ch-accepted-day-generations"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAll() -> [AcceptedDayGenerationRun] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AcceptedDayGenerationRun].self, from: data)) ?? []
    }

    func load(scheduledDate: String) -> AcceptedDayGenerationRun? {
        loadAll().first { $0.scheduledDate == scheduledDate }
    }

    func save(_ run: AcceptedDayGenerationRun) {
        var runs = loadAll().filter { $0.scheduledDate != run.scheduledDate }
        runs.append(run)
        persist(runs)
    }

    func remove(scheduledDate: String) {
        let runs = loadAll().filter { $0.scheduledDate != scheduledDate }
        persist(runs)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ runs: [AcceptedDayGenerationRun]) {
        guard let data = try? JSONEncoder().encode(runs) else { return }
        defaults.set(data, forKey: key)
    }
}
