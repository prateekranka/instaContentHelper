import SwiftUI

struct MiraDealsView: View {
    let store: MiraStore
    let sharedBriefWaiting: Bool
    let needsConsent: Bool
    let onRead: () -> Void
    let onReviewConsent: () -> Void
    let onConfirm: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        MiraPage {
            if sharedBriefWaiting {
                Text("A shared brief is waiting. Finish this brief to open the next one.")
                    .font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
            }
            switch store.dealBriefState {
            case .empty:
                if store.deals.isEmpty {
                    MiraSectionTitle(text: "Share a brand brief to Mira")
                    Text("Share text or a PDF to Mira, or paste the brief here.")
                }
                Button(store.dealBriefState.nextAction.title) { store.beginDealBrief() }
                    .buttonStyle(MiraPrimaryStyle())
            case .editing(let draft), .failed(let draft):
                editor(draft)
            case .reading:
                ProgressView("Reading your brief…")
            case .reconnect(let draft):
                Text(draft.issue ?? "Reconnect to check this brief.")
                Button(store.dealBriefState.nextAction.title, action: onRead)
                    .buttonStyle(MiraPrimaryStyle())
            case .reviewing:
                if let card = store.proposedDeal {
                    switch card {
                    case .reviewing(let draft, let terms):
                        Text("Check these details against your brief.")
                        MiraDealTermsView(terms: terms, source: draft.text)
                        Button(card.nextAction.title, action: onConfirm)
                            .buttonStyle(MiraPrimaryStyle())
                        Button("Edit brief") { store.editDealBrief(draft.text) }.buttonStyle(.bordered)
                    case .saved:
                        EmptyView()
                    }
                }
            }
            if needsConsent {
                Button(MiraNextAction.reviewAIConsent.title, action: onReviewConsent)
                    .buttonStyle(.bordered)
            }
            ForEach(store.deals) { deal in
                MiraDealSummary(deal: deal) { onOpen(deal.id) }
            }
        }
    }

    private func editor(_ draft: MiraDealBriefDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MiraField(title: "Brand brief", text: Binding(
                get: { store.dealBriefState.record?.text ?? draft.text },
                set: { text in store.editDealBrief(text) }))
            PasteButton(payloadType: String.self) { strings in
                store.editDealBrief(strings.joined(separator: "\n\n"))
            }
            .labelStyle(.titleOnly)
            .accessibilityIdentifier("mira.deals.paste")
            if draft.text.utf16.count > 12_000 {
                Text("Shorten the brief to 12,000 characters or fewer.")
            }
            if let issue = draft.issue { Text(issue) }
            Button(store.dealBriefState.nextAction.title, action: onRead)
                .buttonStyle(MiraPrimaryStyle())
                .disabled(!MiraDealBriefInput.canRead(draft.text))
        }
    }
}

struct MiraDealSummary: View {
    let deal: MiraDeal
    let onOpen: () -> Void

    var body: some View {
        MiraFeedCard {
            MiraSectionTitle(text: deal.terms.title)
            MiraDealFeeAndDeadline(terms: deal.terms)
            Button(MiraDealCardState.saved(deal).nextAction.title, action: onOpen)
                .buttonStyle(MiraPrimaryStyle())
                .accessibilityLabel("Open deal for \(deal.terms.title)")
        }
    }
}

private struct MiraDealFeeAndDeadline: View {
    let terms: MiraDealTerms

    var body: some View {
        MiraDealField(label: "Fee", value: terms.fee.isEmpty ? "Check with the brand" : terms.fee)
        MiraDealField(label: "Deadline", value: terms.deadline.isEmpty ? "Check with the brand" : terms.deadlineExcerpt)
    }
}

private struct MiraDealField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
            Text(value)
        }
    }
}

private struct MiraDealTermsView: View {
    let terms: MiraDealTerms
    let source: String

    var body: some View {
        MiraSectionTitle(text: terms.title)
        MiraDealFeeAndDeadline(terms: terms)
        if !terms.checklist.isEmpty {
            MiraSectionTitle(text: "Deliverables")
            ForEach(terms.checklist) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text).font(.headline)
                    Text(item.excerpt).foregroundStyle(MiraTheme.secondaryInk)
                }
            }
        }
        if !terms.disclosures.isEmpty {
            MiraDealField(label: "Disclosures", value: terms.disclosures.joined(separator: ", "))
        }
        if !terms.codes.isEmpty {
            MiraDealField(label: "Codes", value: terms.codes.joined(separator: ", "))
        }
        if !terms.unresolved.isEmpty {
            MiraSectionTitle(text: "Check with the brand")
            ForEach(Array(terms.unresolved.enumerated()), id: \.offset) { _, item in Text(item) }
        }
        DisclosureGroup("Original brief") { Text(source).textSelection(.enabled) }
    }
}

struct MiraDealDetailView: View {
    let store: MiraStore
    let id: UUID

    var body: some View {
        if let deal = store.deals.first(where: { $0.id == id }) {
            content(deal)
        }
    }

    private func content(_ deal: MiraDeal) -> some View {
        let tracker = MiraDealTrackerState(saved: deal.tracker)
        return MiraPage {
            MiraDealTermsView(terms: deal.terms, source: deal.source)
            MiraSectionTitle(text: "Deal tracker")
            trackerRow("Posted", date: tracker.record.postedAt)
            trackerRow("Brand told", date: tracker.record.brandToldAt)
            trackerRow("Confirmed", date: tracker.record.confirmedAt)
            trackerRow("Paid", date: tracker.record.paidAt)
            if let action = tracker.nextAction {
                Button(action.title) {
                    let now = Date()
                    switch tracker {
                    case .toPost: store.trackDeal(id, .posted(now))
                    case .toTellBrand: store.trackDeal(id, .brandTold(now))
                    case .toConfirm: store.trackDeal(id, .confirmed(now))
                    case .toPay: store.trackDeal(id, .paid(now))
                    case .paid: break
                    }
                }
                .buttonStyle(MiraPrimaryStyle())
            }
        }
        .navigationTitle("Deal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trackerRow(_ title: String, date: Date?) -> some View {
        LabeledContent(title, value: date?.formatted(date: .abbreviated, time: .omitted) ?? "Pending")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(date?.formatted(date: .abbreviated, time: .omitted) ?? "Pending")
    }
}
