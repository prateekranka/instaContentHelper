import SwiftUI

struct IntelligenceHomeView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var editingReviewItem: IntelligenceItem?

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: MCOSpace.l) {
                    header
                    NavigationLink {
                        referenceImportDestination
                    } label: {
                        ReferenceImportEntryBlock(isLiveRuntime: services.isLiveSupabaseRuntime)
                    }
                    .buttonStyle(.plain)
                    .disabled(!services.isLiveSupabaseRuntime)
                    if let referenceMessage {
                        ReferenceImportMessageBanner(message: referenceMessage)
                    }
                    NeedsYourCallShelf(
                        items: services.intelligenceHome.needsReview,
                        isReviewing: services.isReviewingReference,
                        onApprove: { item in
                            review(item, action: .approve)
                        },
                        onDismiss: { item in
                            review(item, action: .dismiss)
                        },
                        onEdit: { item in
                            editingReviewItem = item
                        },
                        onOpen: { item in
                            open(item)
                        }
                    )
                    IntelligenceShelf(
                        title: "Ready for this week",
                        items: services.intelligenceHome.readyForThisWeek
                    )
                    SourcePulseShelf(sourcePulse: services.intelligenceHome.sourcePulse)
                    IntelligenceShelf(
                        title: "Idea candidates",
                        items: services.intelligenceHome.ideaCandidates
                    )
                    IntelligenceShelf(
                        title: "Recently used",
                        items: services.intelligenceHome.recentlyUsed
                    )
                    LibraryNavigationShelf(sections: services.intelligenceHome.librarySections)
                }
                .padding(.horizontal, MCOSpace.l)
                .padding(.top, MCOSpace.l)
                .padding(.bottom, 116)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $editingReviewItem) { item in
            ReferenceReviewEditSheet(
                item: item,
                isSaving: services.isReviewingReference
            ) { edit in
                review(item, action: .edit, edit: edit)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Text("MC")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 42, height: 42)
                    .background(MCOTheme.Color.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }

                Spacer()

                NavigationLink {
                    referenceImportDestination
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(services.isLiveSupabaseRuntime ? MCOTheme.Color.ink : MCOTheme.Color.inkMuted)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(!services.isLiveSupabaseRuntime)
                .accessibilityLabel("Open Reference Import")

                FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                    appState.activeMode = .creator
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("MANAGER INTELLIGENCE")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text("Intelligence")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Prepared material for the week.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }

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

    private var referenceMessage: ReferenceImportMessage? {
        if let error = services.lastReferenceImportError?.nilIfBlank {
            return .error(error)
        }

        if let toast = services.referenceImportToast?.nilIfBlank {
            return .success(toast)
        }

        return nil
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

    private func open(_ item: IntelligenceItem) {
        guard
            let sourceURL = item.sourceURL,
            let url = URL(string: sourceURL)
        else {
            return
        }

        openURL(url)
    }
}

struct ReferenceImportEntryBlock: View {
    let isLiveRuntime: Bool

    var body: some View {
        JournalBlock {
            HStack(alignment: .center, spacing: MCOSpace.m) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isLiveRuntime ? MCOTheme.Color.oxblood : MCOTheme.Color.inkMuted)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Reference Import")
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(isLiveRuntime ? "Paste or upload Inspiration sources." : "Connect live Supabase to import references.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MCOSpace.s)

                StatusChip(
                    text: isLiveRuntime ? "Live" : "Fixtures",
                    tone: isLiveRuntime ? .ready : .quiet
                )
            }
        }
    }
}

struct SourcePulseShelf: View {
    let sourcePulse: SourcePulseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: sourcePulse.title, trailing: sourcePulse.subtitle)

            VStack(spacing: 0) {
                ForEach(sourcePulse.references) { reference in
                    ReferencePulseRow(reference: reference)
                    Hairline()
                }
            }
        }
    }
}

struct ReferencePulseRow: View {
    let reference: ReferenceSummary

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: reference.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(reference.state.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(reference.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                Text("\(reference.sourceType) - \(reference.note)")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            StatusChip(text: reference.state.label, tone: reference.state.tone)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct NeedsYourCallShelf: View {
    let items: [IntelligenceItem]
    let isReviewing: Bool
    let onApprove: (IntelligenceItem) -> Void
    let onDismiss: (IntelligenceItem) -> Void
    let onEdit: (IntelligenceItem) -> Void
    let onOpen: (IntelligenceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "Needs your call", trailing: "\(items.count)")

            if items.isEmpty {
                HStack(alignment: .center, spacing: MCOSpace.m) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(MCOTheme.Color.sageDeep)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                        Text("No import rows waiting")
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(MCOTheme.Color.ink)
                        Text("New unknown rows and candidate accounts will land here.")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    }

                    Spacer(minLength: MCOSpace.s)
                }
                .padding(.vertical, MCOSpace.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        NeedsYourCallRow(
                            item: item,
                            isReviewing: isReviewing,
                            onApprove: { onApprove(item) },
                            onDismiss: { onDismiss(item) },
                            onEdit: { onEdit(item) },
                            onOpen: { onOpen(item) }
                        )
                        Hairline()
                    }
                }
            }
        }
    }
}

struct NeedsYourCallRow: View {
    let item: IntelligenceItem
    let isReviewing: Bool
    let onApprove: () -> Void
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack(alignment: .top, spacing: MCOSpace.m) {
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    ReferenceImportTypeChipView(typeChip: item.typeChip ?? .unknown)
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(item.state.accent)
                        .frame(width: 34, alignment: .leading)
                }
                .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    Text(item.subtitle)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: MCOSpace.s)

                StatusChip(text: item.trailingNote, tone: .warning)
            }

            HStack(spacing: MCOSpace.s) {
                ReviewActionButton(title: "Approve", symbol: "checkmark", isDisabled: isReviewing || item.reviewItem == nil, action: onApprove)
                ReviewActionButton(title: "Dismiss", symbol: "xmark", isDisabled: isReviewing || item.reviewItem == nil, action: onDismiss)
                ReviewActionButton(title: "Edit", symbol: "pencil", isDisabled: isReviewing || item.reviewItem == nil, action: onEdit)
                ReviewActionButton(title: "Open", symbol: "arrow.up.right", isDisabled: item.sourceURL == nil, action: onOpen)
            }
            .padding(.leading, 66 + MCOSpace.m)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct ReviewActionButton: View {
    let title: String
    let symbol: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? MCOTheme.Color.inkMuted : MCOTheme.Color.oxblood)
        .background(MCOTheme.Color.paperRaised.opacity(isDisabled ? 0.36 : 0.78))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct IntelligenceShelf: View {
    let title: String
    let items: [IntelligenceItem]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: title, trailing: nil)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    IntelligenceShelfRow(item: item)
                    Hairline()
                }
            }
        }
    }
}

struct IntelligenceShelfRow: View {
    let item: IntelligenceItem

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(item.state.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(item.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(item.kind.rawValue)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.xs) {
                Text(item.trailingNote)
                    .font(MCOType.caption)
                    .foregroundStyle(item.state.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, MCOSpace.s)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryNavigationShelf: View {
    let sections: [IntelligenceLibrarySection]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "Library", trailing: "Counts stay secondary.")

            VStack(spacing: 0) {
                ForEach(sections) { section in
                    LibraryNavigationRow(section: section)
                    Hairline()
                }
            }
        }
    }
}

struct LibraryNavigationRow: View {
    let section: IntelligenceLibrarySection

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: section.symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(section.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(section.subtitle)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.s) {
                Text("\(section.count)")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct ShelfHeader: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Spacer(minLength: MCOSpace.s)
            if let trailing {
                Text(trailing)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }
        }
    }
}

extension IntelligenceReviewState {
    var accent: Color {
        switch self {
        case .ready, .approved:
            MCOTheme.Color.sageDeep
        case .needsReview:
            MCOTheme.Color.brass
        case .usedThisWeek:
            MCOTheme.Color.inkMuted
        }
    }

    var tone: ChipTone {
        switch self {
        case .ready, .approved:
            .ready
        case .needsReview:
            .warning
        case .usedThisWeek:
            .quiet
        }
    }
}

#Preview {
    IntelligenceHomeView()
        .environment(AppState())
        .environment(AppServices.preview)
}
