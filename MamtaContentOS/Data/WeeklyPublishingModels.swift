import Foundation

extension WeeklyPlan {
    var softLockedForPublish: WeeklyPlan {
        var publishedPlan = self
        publishedPlan.isSoftLocked = true
        publishedPlan.readinessLine = publishedPlan.readinessSummary
        publishedPlan.days = publishedPlan.days.map { day in
            var publishedDay = day
            publishedDay.isSoftLocked = true
            return publishedDay
        }
        return publishedPlan
    }

    var readinessSummary: String {
        let readyCount = days.filter { $0.state == .planned }.count
        let backupCount = days.filter { $0.state == .backup }.count
        let openCount = days.filter { $0.state == .open }.count
        return "\(readyCount) ready, \(backupCount) backup, \(openCount) open"
    }
}

extension DailyCard {
    static func publishedCards(from plan: WeeklyPlan) -> [DailyCard] {
        plan.days.map { day in
            DailyCard(
                id: day.id,
                title: day.title,
                context: contextLine(for: day, plan: plan),
                effortLabel: effortLabel(for: day),
                whyToday: day.reason,
                sourceNote: "\(day.source.rawValue) source",
                scheduledDate: day.scheduledDate,
                scenes: defaultScenes(for: day)
            )
        }
    }

    static func bestTodayCard(from cards: [DailyCard]) -> DailyCard? {
        let today = SupabaseDateFormatting.todayDateString()
        return cards.first { $0.scheduledDate == today }
            ?? cards.first { $0.title == DailyCard.raceWeekToday.title }
            ?? cards.first
    }

    private static func contextLine(for day: WeeklyDay, plan: WeeklyPlan) -> String {
        let weekday = day.weekday.prefix(1).uppercased() + day.weekday.dropFirst().lowercased()
        return "\(weekday), \(plan.title)"
    }

    private static func effortLabel(for day: WeeklyDay) -> String {
        switch day.state {
        case .planned:
            "Easy - 12 min"
        case .backup:
            "Backup - 8 min"
        case .open:
            "Open - confirm"
        }
    }

    private static func defaultScenes(for day: WeeklyDay) -> [ShotScene] {
        switch day.source {
        case .brand:
            [
                ShotScene(number: 1, title: "Product or kit detail", duration: "3 sec", symbol: "shoeprints.fill"),
                ShotScene(number: 2, title: "Training movement", duration: "4 sec", symbol: "figure.run"),
                ShotScene(number: 3, title: "Disclosure-safe close", duration: "3 sec", symbol: "checkmark.seal")
            ]
        case .moment:
            [
                ShotScene(number: 1, title: "Quiet context", duration: "3 sec", symbol: "camera"),
                ShotScene(number: 2, title: "One human detail", duration: "4 sec", symbol: "person.2"),
                ShotScene(number: 3, title: "Soft closing line", duration: "3 sec", symbol: "heart")
            ]
        default:
            [
                ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                ShotScene(number: 2, title: day.title, duration: "5 sec", symbol: "figure.run"),
                ShotScene(number: 3, title: "One useful takeaway", duration: "4 sec", symbol: "text.quote")
            ]
        }
    }
}
