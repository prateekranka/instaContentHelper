import Foundation
import Synchronization

enum SupabaseDateFormatting {
    private struct Formatters {
        var calendarDays: [String: DateFormatter] = [:]
        let timestamp = ISO8601DateFormatter()
    }

    private static let formatters = Mutex(Formatters())

    private static func withFormatter<T>(
        format: String,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
        localeIdentifier: String = "en_US_POSIX",
        _ body: (DateFormatter) -> T
    ) -> T {
        formatters.withLock { cache in
            let key = format + ":" + timeZone.identifier + ":" + localeIdentifier
            let formatter: DateFormatter
            if let cached = cache.calendarDays[key] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                formatter.locale = Locale(identifier: localeIdentifier)
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                cache.calendarDays[key] = formatter
            }
            return body(formatter)
        }
    }

    static func isoTimestampString() -> String {
        formatters.withLock { $0.timestamp.string(from: Date()) }
    }

    static func timestamp(from value: String) -> Date? {
        formatters.withLock { cache in
            cache.timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = cache.timestamp.date(from: value)
            cache.timestamp.formatOptions = [.withInternetDateTime]
            return fractional ?? cache.timestamp.date(from: value)
        }
    }

    static func timeOfDay(from date: Date, timeZone: TimeZone = .current) -> String {
        withFormatter(format: "h:mm a", timeZone: timeZone) { $0.string(from: date) }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
