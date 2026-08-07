import Foundation

struct ContentCategoryOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String

    static let otherID = "other"

    static let catalog: [ContentCategoryOption] = [
        ContentCategoryOption(id: "fitness", label: "Fitness"),
        ContentCategoryOption(id: "books", label: "Books & movies"),
        ContentCategoryOption(id: "food", label: "Food"),
        ContentCategoryOption(id: "travel", label: "Travel"),
        ContentCategoryOption(id: "lifestyle", label: "Lifestyle"),
        ContentCategoryOption(id: "makeup", label: "Makeup"),
        ContentCategoryOption(id: "tech", label: "Tech"),
        ContentCategoryOption(id: "finance", label: "Finance"),
        ContentCategoryOption(id: "parenting", label: "Parenting"),
        ContentCategoryOption(id: "gaming", label: "Gaming"),
        ContentCategoryOption(id: otherID, label: "Other"),
    ]
}

struct ContentCategorySelection: Equatable, Sendable {
    var selectedIDs: [String]
    var customOtherLabel: String

    static let maxSelectionCount = 3

    static func from(contentPillars: [String]) -> ContentCategorySelection {
        var selectedIDs: [String] = []
        var customOtherLabel = ""

        for pillar in contentPillars.prefix(maxSelectionCount) {
            let trimmed = pillar.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let match = ContentCategoryOption.catalog.first(where: {
                $0.id != ContentCategoryOption.otherID &&
                    $0.label.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }) {
                if !selectedIDs.contains(match.id) {
                    selectedIDs.append(match.id)
                }
                continue
            }

            if !selectedIDs.contains(ContentCategoryOption.otherID) {
                selectedIDs.append(ContentCategoryOption.otherID)
                customOtherLabel = trimmed
            }
        }

        return ContentCategorySelection(selectedIDs: selectedIDs, customOtherLabel: customOtherLabel)
    }

    func resolvedContentPillars() -> [String] {
        selectedIDs.compactMap { id in
            if id == ContentCategoryOption.otherID {
                let trimmed = customOtherLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return ContentCategoryOption.catalog.first(where: { $0.id == id })?.label
        }
    }

    func label(for id: String) -> String? {
        ContentCategoryOption.catalog.first(where: { $0.id == id })?.label
    }

    var summarySubtitle: String {
        let pillars = resolvedContentPillars()
        guard !pillars.isEmpty else { return "Not set" }
        return "\(pillars.count) selected"
    }

    mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.removeAll { $0 == id }
            if id == ContentCategoryOption.otherID {
                customOtherLabel = ""
            }
            return
        }

        guard selectedIDs.count < Self.maxSelectionCount else { return }
        selectedIDs.append(id)
    }

    var includesOther: Bool {
        selectedIDs.contains(ContentCategoryOption.otherID)
    }

    var isValid: Bool {
        guard !selectedIDs.isEmpty, selectedIDs.count <= Self.maxSelectionCount else { return false }
        if includesOther {
            return !customOtherLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}
