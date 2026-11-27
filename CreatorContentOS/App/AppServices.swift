import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
    let isLiveSupabaseRuntime: Bool
    let aiConsentStore: any AIConsentStoring
    private(set) var aiConsent = MiraAIConsentState.notAsked
    var isAIConsentSheetPresented = false

    init(isLiveSupabaseRuntime: Bool, aiConsentStore: any AIConsentStoring) {
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.aiConsentStore = aiConsentStore
        refreshAIConsent()
    }

    func refreshAIConsent() {
        aiConsent = aiConsent.handle(.read(aiConsentStore.load(), currentVersion: AIConsentPolicy.currentVersion))
    }
}
