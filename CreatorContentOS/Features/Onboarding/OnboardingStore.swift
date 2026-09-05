import Foundation

/// Local onboarding progress cache — workspace + creator scoped only.
/// Not the live onboarding gate; profile `onboarding_state` is source of truth.
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

struct WorkspaceScopedOnboardingStore: OnboardingStoring, @unchecked Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    private let defaults: UserDefaults

    private enum KeySuffix {
        static let progress = "progress"
        static let data = "data"
    }

    init(
        workspaceID: UUID,
        creatorID: UUID,
        defaults: UserDefaults = .standard
    ) {
        self.workspaceID = workspaceID
        self.creatorID = creatorID
        self.defaults = defaults
    }

    private func scopedKey(_ suffix: String) -> String {
        "ch-onboarding.\(workspaceID.uuidString).\(creatorID.uuidString).\(suffix)"
    }

    func isComplete() -> Bool {
        false
    }

    func loadProgress() -> OnboardingProgress? {
        guard let raw = defaults.string(forKey: scopedKey(KeySuffix.progress)),
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
        defaults.set(json, forKey: scopedKey(KeySuffix.progress))
    }

    func clearProgress() {
        defaults.removeObject(forKey: scopedKey(KeySuffix.progress))
    }

    func loadCompletedData() -> OnboardingCompletedData? {
        guard let raw = defaults.string(forKey: scopedKey(KeySuffix.data)),
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
        defaults.set(json, forKey: scopedKey(KeySuffix.data))
    }

    func markComplete(with data: OnboardingCompletedData) {
        saveCompletedData(data)
        clearProgress()
    }

    func resetAll() {
        clearProgress()
        defaults.removeObject(forKey: scopedKey(KeySuffix.data))
    }
}

enum OnboardingPresentationPolicy {
#if DEBUG
    /// When `MCO_FORCE_ONBOARDING=1`, keep the five-step flow visible for QA even if the
    /// loaded profile is `established` (e.g. fixture HYROX). Does not mutate the profile.
    static var forceOnboardingForQA: Bool {
        ProcessInfo.processInfo.environment["MCO_FORCE_ONBOARDING"] == "1"
    }
#endif

    /// Profile-backed gate used by the live shell.
    static func shouldPresent(
        presentation: CreatorOnboardingPresentation,
        sessionDismissed: Bool
    ) -> Bool {
#if DEBUG
        if forceOnboardingForQA, !sessionDismissed {
            return true
        }
#endif
        guard presentation.shouldForceOnboardingFlow else { return false }
        return !sessionDismissed
    }

    /// Legacy shim for `OnboardingViewModel`; live shell must not use this as the gate.
    static func shouldPresent(
        store: any OnboardingStoring,
        sessionDismissed: Bool
    ) -> Bool {
        guard !store.isComplete() else { return false }
        return !sessionDismissed
    }
}

/// Legacy global store retained for DEBUG reset helpers and fixture UI only.
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

#if DEBUG
extension UserDefaultsOnboardingStore {
    /// Clears legacy global onboarding keys for DEBUG launch flags.
    static func resetLegacyGlobalKeys(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "ch-onboarding-progress")
        defaults.removeObject(forKey: "ch-onboarding-done")
        defaults.removeObject(forKey: "ch-onboarding-data")
    }
}
#endif
