import SwiftUI

struct YouReferencesView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    @State private var editingReviewItem: IntelligenceItem?

    var body: some View {
        YouDestinationScaffold(
            title: "References",
            subtitle: "Save reels, audio, and inspiration accounts for future drafts.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                importBlock
                importFeedback
                needsReviewBlock
                confirmedBlock
                growthBlock
                recentlyUsedBlock
                libraryBlock
            }
        }
        .accessibilityIdentifier("you.screen.references")
        .sheet(item: $editingReviewItem) { item in
            ReferenceReviewEditSheet(
                item: item,
                isSaving: services.isReviewingReference
            ) { edit in
                review(item, action: .edit, edit: edit)
            }
        }
    }

    // MARK: - Import entry

    private var importBlock: some View {
        PocketSheetBlock(header: "Add references") {
            NavigationLink {
                referenceImportDestination
            } label: {
                PocketSheetRow(
                    title: "Import inspiration",
                    subtitle: "Paste links, handles, notes, or upload CSV."
                )
            }
            .buttonStyle(.plain)
            .disabled(!services.isLiveSupabaseRuntime)
            .opacity(services.isLiveSupabaseRuntime ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var importFeedback: some View {
        if let error = services.lastReferenceImportError?.nilIfBlank {
            Text(error)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.validationAttention)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let toast = services.referenceImportToast?.nilIfBlank {
            Text(toast)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Needs your call

    @ViewBuilder
    private var needsReviewBlock: some View {
        let items = services.intelligenceHome.needsReview
        if !items.isEmpty {
            PocketSheetBlock(header: "Needs your call") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        needsReviewRow(item)
                        if index < items.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }
        }
    }

    private func needsReviewRow(_ item: IntelligenceItem) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .frame(width: 34, height: 34)
                    .background(PocketSheetTheme.Color.fillMuted)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: PocketSheetSpace.s)

                Text(item.trailingNote)
                    .font(PocketSheetType.chip)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            HStack(spacing: PocketSheetSpace.xs) {
                reviewPill(title: "Approve", isDisabled: item.reviewItem == nil) {
                    review(item, action: .approve)
                }
                reviewPill(title: "Dismiss", isDisabled: item.reviewItem == nil) {
                    review(item, action: .dismiss)
                }
                reviewPill(title: "Edit", isDisabled: item.reviewItem == nil) {
                    editingReviewItem = item
                }
            }
            .padding(.leading, 34 + PocketSheetSpace.s)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
    }

    private func reviewPill(title: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        let isDisabled = isDisabled || services.isReviewingReference
        return Button(action: action) {
            Text(title)
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    // MARK: - Confirmed references

    private var confirmedBlock: some View {
        let references = services.intelligenceHome.sourcePulse.references.filter { $0.state != .needsReview }
        return PocketSheetBlock(header: "Confirmed references") {
            if references.isEmpty {
                Text("No references yet — add one above.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.vertical, PocketSheetSpace.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                        confirmedRow(reference)
                        if index < references.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }
        }
    }

    private func confirmedRow(_ reference: ReferenceSummary) -> some View {
        HStack(spacing: PocketSheetSpace.s) {
            Image(systemName: reference.symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineLimit(1)
                Text("\(reference.sourceType) - \(reference.note)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: PocketSheetSpace.s)

            PocketSheetChip(text: reference.state.label, isEmphasized: reference.state == .approved)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
    }

    // MARK: - Growth references

    @ViewBuilder
    private var growthBlock: some View {
        let references = services.intelligenceHome.growthReferences
        if !references.isEmpty {
            PocketSheetBlock(header: "Growth references") {
                VStack(spacing: 0) {
                    ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                        growthRow(reference)
                        if index < references.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }
        }
    }

    private func growthRow(_ reference: GrowthReference) -> some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reference.title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineLimit(1)
                Text(reference.summary)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PocketSheetSpace.s)

            Text(reference.relevanceLabel)
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
    }

    // MARK: - Recently used

    @ViewBuilder
    private var recentlyUsedBlock: some View {
        let items = services.intelligenceHome.recentlyUsed
        if !items.isEmpty {
            PocketSheetBlock(header: "Recently used") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        recentlyUsedRow(item)
                        if index < items.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }
        }
    }

    private func recentlyUsedRow(_ item: IntelligenceItem) -> some View {
        HStack(spacing: PocketSheetSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: PocketSheetSpace.s)

            Text(item.kind.rawValue)
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
    }

    // MARK: - Library

    @ViewBuilder
    private var libraryBlock: some View {
        let sections = services.intelligenceHome.librarySections
        if !sections.isEmpty {
            PocketSheetBlock(header: "Library") {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        libraryRow(section)
                        if index < sections.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }
        }
    }

    private func libraryRow(_ section: IntelligenceLibrarySection) -> some View {
        HStack(spacing: PocketSheetSpace.s) {
            Image(systemName: section.symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineLimit(1)
                Text(section.subtitle)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: PocketSheetSpace.s)

            Text("\(section.count)")
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
    }

    // MARK: - Import wiring (mirrors IntelligenceHomeView)

    private var referenceImportDestination: some View {
        ReferenceImportView(
            isLiveRuntime: services.isLiveSupabaseRuntime,
            previewReferenceImport: { rawText, inputType, filename in
                guard let preview = await services.previewReferenceImportImmediately(
                    rawText: rawText,
                    inputType: inputType,
                    filename: filename
                ) else {
                    throw RepositoryError.notConfigured(
                        services.lastReferenceImportError ?? "Reference import preview failed."
                    )
                }
                return preview
            },
            confirmReferenceImport: { rawText, inputType, filename, previewChecksum in
                guard let result = await services.confirmReferenceImportImmediately(
                    rawText: rawText,
                    inputType: inputType,
                    filename: filename,
                    previewChecksum: previewChecksum
                ) else {
                    throw RepositoryError.notConfigured(
                        services.lastReferenceImportError ?? "Reference import failed."
                    )
                }
                return result
            },
            onFinished: {
                Task {
                    await services.refreshIntelligenceHomeImmediately()
                }
            }
        )
    }

    private func review(
        _ item: IntelligenceItem,
        action: ReferenceReviewAction,
        edit: ReferenceReviewEdit? = nil
    ) {
        guard let reviewItem = item.reviewItem else { return }
        services.reviewReferenceItem(
            ReferenceReviewRequest(
                item: reviewItem,
                action: action,
                edit: edit
            )
        )
    }
}
