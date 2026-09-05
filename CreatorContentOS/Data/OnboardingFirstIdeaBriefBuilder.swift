import Foundation
import CryptoKit

enum OnboardingFirstIdeaBriefBuilder {
    static func buildDayBrief(from record: OnboardingRecord) -> String {
        var sections: [String] = []

        let interests = record.interestLabels
        if !interests.isEmpty {
            sections.append("Interests: \(interests.joined(separator: ", ")).")
        }

        if let startingPoint = record.startingPoint?.nilIfBlank {
            let label = startingPoint == "already_posting"
                ? "Already posting regularly"
                : "Just starting out"
            sections.append("Starting point: \(label).")
        }

        if !record.tasteExampleTitles.isEmpty {
            sections.append(
                "Style references: \(record.tasteExampleTitles.joined(separator: "; "))."
            )
        }

        if !record.formats.isEmpty {
            sections.append("Preferred formats: \(record.formats.joined(separator: ", ")).")
        }

        if let time = record.timeToCreate?.nilIfBlank {
            let minutes: String
            switch time {
            case "five_to_ten": minutes = "8"
            case "ten_to_thirty": minutes = "20"
            case "thirty_plus": minutes = "40"
            default: minutes = "20"
            }
            sections.append("Shoot time budget: about \(minutes) minutes.")
        }

        if !record.contentLanguage.isEmpty {
            sections.append("Content language: \(record.contentLanguage).")
        }

        if let showFace = record.showFace {
            sections.append(showFace ? "Creator shows face on camera." : "No face on camera.")
        }
        if let useVoice = record.useVoice {
            sections.append(useVoice ? "Voiceover allowed." : "No voiceover.")
        }

        for (questionID, answer) in record.contextAnswers {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sections.append("Context (\(questionID)): \(trimmed).")
        }

        if let note = record.creatorNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            sections.append("Extra direction: \(note).")
        }

        sections.append("First idea after onboarding. One shootable reel for today.")

        let brief = sections.joined(separator: " ")
        return brief.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fingerprint(for brief: String) -> String {
        let digest = SHA256.hash(data: Data(brief.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
