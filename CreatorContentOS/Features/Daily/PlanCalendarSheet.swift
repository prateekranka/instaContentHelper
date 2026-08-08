import SwiftUI

/// Full calendar picker presented when the Plan date header is tapped.
struct PlanCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date
    let packageStatusForDate: (String) -> String?
    let onSelectDate: (Date) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                    calendarLegend
                    monthHeader
                    weekdayHeader
                    monthGrid
                }
                .padding(PocketSheetSpace.l)
            }
            .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
            .navigationTitle("Choose a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("plan.calendar.done")
                }
            }
        }
        .tint(PocketSheetTheme.Color.ink)
        .accessibilityIdentifier("plan.calendar.sheet")
    }

    private var calendarLegend: some View {
        HStack(spacing: PocketSheetSpace.m) {
            legendItem(color: PocketSheetTheme.Color.statusReady, label: "Ready")
            legendItem(color: PocketSheetTheme.Color.statusDraft, label: "Draft")
            HStack(spacing: PocketSheetSpace.xs) {
                Circle()
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                    .frame(width: 8, height: 8)
                Text("Empty")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: filled ready, muted draft, none empty")
        .accessibilityIdentifier("plan.calendar.legend")
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: PocketSheetSpace.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()
            Text(monthTitle(for: visibleMonth))
                .font(PocketSheetType.rowTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        let symbols = Calendar(identifier: .gregorian).veryShortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysInVisibleMonth()
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: PocketSheetSpace.xs
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    calendarDayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .accessibilityIdentifier("plan.calendar")
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let dateString = Self.dateString(from: date)
        let state = PlanCalendarDayState.from(packageStatus: packageStatusForDate(dateString))
        let isSelected = dateString == Self.dateString(from: selectedDate)
        let isSelectable = date >= Self.startOfToday()
        let dayNumber = Calendar(identifier: .gregorian).component(.day, from: date)

        return Button {
            selectedDate = date
            onSelectDate(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(
                        isSelected
                            ? PocketSheetTheme.Color.inverseInk
                            : (isSelectable ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.inkMuted.opacity(0.45))
                    )
                Group {
                    switch state {
                    case .ready:
                        Circle()
                            .fill(PocketSheetTheme.Color.statusReady)
                            .frame(width: 6, height: 6)
                    case .draft:
                        Circle()
                            .fill(PocketSheetTheme.Color.statusDraft)
                            .frame(width: 6, height: 6)
                    case .empty:
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected
                    ? PocketSheetTheme.Color.fillMuted
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.ink, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .accessibilityLabel(calendarAccessibilityLabel(dateString: dateString, dayNumber: dayNumber, state: state))
        .accessibilityIdentifier("plan.calendar.day.\(dateString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func calendarAccessibilityLabel(
        dateString: String,
        dayNumber: Int,
        state: PlanCalendarDayState
    ) -> String {
        let stateLabel: String
        switch state {
        case .ready: stateLabel = "ready"
        case .draft: stateLabel = "draft"
        case .empty: stateLabel = "empty"
        }
        return "Day \(dayNumber), \(stateLabel), \(dateString)"
    }

    private func shiftMonth(by value: Int) {
        guard let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: value, to: visibleMonth) else {
            return
        }
        visibleMonth = next
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func daysInVisibleMonth() -> [Date?] {
        let calendar = Calendar(identifier: .gregorian)
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeekdayIndex = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else {
            return []
        }

        let leadingBlanks = (firstWeekdayIndex - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private static func startOfToday() -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
