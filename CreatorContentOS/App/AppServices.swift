import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
    let isLiveSupabaseRuntime: Bool
    let aiConsentStore: any AIConsentStoring
    var aiConsentAllowsOutbound = false
    var isAIConsentSheetPresented = false

    init(isLiveSupabaseRuntime: Bool, aiConsentStore: any AIConsentStoring) {
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.aiConsentStore = aiConsentStore
        refreshAIConsentFlagsFromStore()
    }
}
