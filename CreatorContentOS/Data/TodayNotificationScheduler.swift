import Foundation
import UserNotifications

struct TodayNotificationSchedule: Hashable, Sendable {
    var identifier: String
    var cardID: UUID
    var title: String
    var body: String
    var scheduledDate: String
    var hour: Int
    var minute: Int
}

@MainActor
protocol TodayNotificationScheduling {
    @discardableResult
    func scheduleTodayReminder(
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> TodayNotificationSchedule?

    func cancelTodayReminder(for context: WorkspaceContext) async
}

struct NoopTodayNotificationScheduler: TodayNotificationScheduling {
    func scheduleTodayReminder(
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> TodayNotificationSchedule? {
        nil
    }

    func cancelTodayReminder(for context: WorkspaceContext) async {}
}

struct LocalTodayNotificationScheduler: TodayNotificationScheduling {
    private let center: UNUserNotificationCenter
    private let hour: Int
    private let minute: Int
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        hour: Int = 8,
        minute: Int = 0,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.hour = hour
        self.minute = minute
        self.calendar = calendar
    }

    func scheduleTodayReminder(
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> TodayNotificationSchedule? {
        guard card.completionState == nil else {
            await cancelTodayReminder(for: context)
            return nil
        }

        let schedule = TodayNotificationSchedule(
            identifier: Self.identifier(for: context),
            cardID: card.id,
            title: "Today's reel is ready",
            body: notificationBody(for: card),
            scheduledDate: card.scheduledDate ?? SupabaseDateFormatting.todayDateString(),
            hour: hour,
            minute: minute
        )

        guard let dateComponents = dateComponents(for: schedule) else {
            return nil
        }

        let granted = try await requestAuthorizationIfNeeded()
        guard granted else {
            return nil
        }

        center.removePendingNotificationRequests(withIdentifiers: [schedule.identifier])

        let content = UNMutableNotificationContent()
        content.title = schedule.title
        content.body = schedule.body
        content.threadIdentifier = "creator-today"
        content.categoryIdentifier = "creator-today"
        content.interruptionLevel = .passive

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        guard trigger.nextTriggerDate() != nil else {
            return nil
        }

        let request = UNNotificationRequest(
            identifier: schedule.identifier,
            content: content,
            trigger: trigger
        )
        try await add(request)
        return schedule
    }

    func cancelTodayReminder(for context: WorkspaceContext) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(for: context)]
        )
    }

    private static func identifier(for context: WorkspaceContext) -> String {
        "creator.today.\(context.workspaceID.uuidString).\(context.creatorID.uuidString)"
    }

    private func notificationBody(for card: DailyCard) -> String {
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return "Today's card is ready."
        }

        return title
    }

    private func dateComponents(for schedule: TodayNotificationSchedule) -> DateComponents? {
        guard let date = Self.parseDate(schedule.scheduledDate) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0
        return components
    }

    private func requestAuthorizationIfNeeded() async throws -> Bool {
        let authorizationStatus = await authorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await requestAuthorization()
        @unknown default:
            return false
        }
    }

    private func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .provisional]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func parseDate(_ rawDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDate)
    }
}
