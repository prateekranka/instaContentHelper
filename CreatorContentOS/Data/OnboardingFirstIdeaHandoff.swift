import Foundation

enum OnboardingFirstIdeaHandoffStatus: String, Hashable, Sendable {
    case preparing
    case skippedExistingReady = "skipped_existing_ready"
    case completed
    case failed
}

struct OnboardingFirstIdeaHandoffPlan: Hashable, Sendable {
    var scheduledDate: String
    var dayBrief: String
    var briefFingerprint: String
    var shouldGenerate: Bool
    var skipReason: OnboardingFirstIdeaHandoffStatus?
    /// When true, an existing draft may be replaced during first-idea retry.
    var confirmOverwrite: Bool
    /// When true, generation already produced a complete draft; retry only promotes it.
    var makeAvailableOnly: Bool
}

struct OnboardingFirstIdeaGeneratedDraftSnapshot: Hashable, Sendable {
    var title: String
    var script: String
    var caption: String
}

enum OnboardingFirstIdeaPackageEditDetector {
    /// Non-empty generated fields alone are not treated as a user edit.
    static func hasUserEditedPackage(
        packageStatus: String?,
        packageTitle: String?,
        packageScript: String?,
        packageCaption: String?,
        lastGeneratedSnapshot: OnboardingFirstIdeaGeneratedDraftSnapshot?
    ) -> Bool {
        guard let packageStatus,
              DayPackageLifecycleStatus.isDraftPackage(packageStatus) else {
            return false
        }
        guard let lastGeneratedSnapshot else {
            return false
        }

        let title = packageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let script = packageScript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = packageCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title != lastGeneratedSnapshot.title
            || script != lastGeneratedSnapshot.script
            || caption != lastGeneratedSnapshot.caption
    }

    static func isCompleteGeneratedDraft(
        packageTitle: String?,
        packageScript: String?,
        packageCaption: String?
    ) -> Bool {
        let title = packageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let script = packageScript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = packageCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty && !script.isEmpty && !caption.isEmpty
    }
}

enum OnboardingFirstIdeaHandoffPlanner {
    static func plan(
        scheduledDate: String,
        record: OnboardingRecord,
        existingPackageStatus: String?,
        hasUserEditedPackage: Bool,
        firstIdeaHandoffStatus: String? = nil,
        existingDraftIsComplete: Bool = false
    ) -> OnboardingFirstIdeaHandoffPlan {
        let brief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(from: record)
        let fingerprint = OnboardingFirstIdeaBriefBuilder.fingerprint(for: brief)
        let isRetryAfterFailure = firstIdeaHandoffStatus == OnboardingFirstIdeaHandoffStatus.failed.rawValue
        let isDraftLike = DayPackageLifecycleStatus.isDraftPackage(existingPackageStatus)
        let confirmOverwrite = isRetryAfterFailure && isDraftLike

        if let status = existingPackageStatus,
           DayPackageLifecycleStatus.readyOrDecision.contains(status) {
            return OnboardingFirstIdeaHandoffPlan(
                scheduledDate: scheduledDate,
                dayBrief: brief,
                briefFingerprint: fingerprint,
                shouldGenerate: false,
                skipReason: .skippedExistingReady,
                confirmOverwrite: false,
                makeAvailableOnly: false
            )
        }

        if hasUserEditedPackage {
            return OnboardingFirstIdeaHandoffPlan(
                scheduledDate: scheduledDate,
                dayBrief: brief,
                briefFingerprint: fingerprint,
                shouldGenerate: false,
                skipReason: .skippedExistingReady,
                confirmOverwrite: false,
                makeAvailableOnly: false
            )
        }

        if isRetryAfterFailure, isDraftLike, existingDraftIsComplete {
            return OnboardingFirstIdeaHandoffPlan(
                scheduledDate: scheduledDate,
                dayBrief: brief,
                briefFingerprint: fingerprint,
                shouldGenerate: false,
                skipReason: nil,
                confirmOverwrite: confirmOverwrite,
                makeAvailableOnly: true
            )
        }

        return OnboardingFirstIdeaHandoffPlan(
            scheduledDate: scheduledDate,
            dayBrief: brief,
            briefFingerprint: fingerprint,
            shouldGenerate: true,
            skipReason: nil,
            confirmOverwrite: confirmOverwrite,
            makeAvailableOnly: false
        )
    }

    static func firstIdeaHandoffPayload(
        scheduledDate: String,
        status: OnboardingFirstIdeaHandoffStatus,
        briefFingerprint: String
    ) -> [String: String] {
        [
            "scheduled_date": scheduledDate,
            "status": status.rawValue,
            "brief_fingerprint": briefFingerprint
        ]
    }
}

enum OnboardingFirstIdeaHandoffResult: Equatable, Sendable {
    case completed(navigatedToday: Bool)
    case skippedExistingReady
    case persistFailed
    case generationFailed(message: String)
}
