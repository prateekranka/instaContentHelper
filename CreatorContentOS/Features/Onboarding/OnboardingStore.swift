import Foundation

/// Local first-run persistence — keys mirror prototype `ch-onboarding-*`.
protocol OnboardingStoring: Sendable {
    func isComplete() -> Bool
    func loadProgress() -> OnboardingProgress?
    func saveProgress(_ progress: OnboardingProgress)
    func clearProgress()
    func loadCompletedData() -> OnboardingCompletedData?
    func saveCompletedData(_ data: OnboardingCompletedData)
    func markComplete(with data: OnboardingCompletedData)
    func resetAll()
}

struct UserDefaultsOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    private enum Key {
        static let progress = "ch-onboarding-progress"
        static let done = "ch-onboarding-done"
        static let data = "ch-onboarding-data"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isComplete() -> Bool {
        defaults.string(forKey: Key.done) == "1"
    }

    func loadProgress() -> OnboardingProgress? {
        guard let raw = defaults.string(forKey: Key.progress),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(OnboardingProgress.self, from: data)
    }

    func saveProgress(_ progress: OnboardingProgress) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(progress),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Key.progress)
    }

    func clearProgress() {
        defaults.removeObject(forKey: Key.progress)
    }

    func loadCompletedData() -> OnboardingCompletedData? {
        guard let raw = defaults.string(forKey: Key.data),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(OnboardingCompletedData.self, from: data)
    }

    func saveCompletedData(_ data: OnboardingCompletedData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(data),
              let json = String(data: encoded, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Key.data)
    }

    func markComplete(with data: OnboardingCompletedData) {
        saveCompletedData(data)
        defaults.set("1", forKey: Key.done)
        clearProgress()
    }

    func resetAll() {
        clearProgress()
        defaults.removeObject(forKey: Key.done)
        defaults.removeObject(forKey: Key.data)
    }
}

enum OnboardingPresentationPolicy {
    /// True when first-run should cover the shell (not complete and not soft-dismissed this session).
    static func shouldPresent(
        store: any OnboardingStoring,
        sessionDismissed: Bool
    ) -> Bool {
        guard !store.isComplete() else { return false }
        return !sessionDismissed
    }
}
