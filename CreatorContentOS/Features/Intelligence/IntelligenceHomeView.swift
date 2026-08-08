import SwiftUI

struct IntelligenceHomeView: View {
    @Environment(\.chromePalette) private var chrome
    enum Presentation {
        /// Admin References tab with screen chrome.
        case standalone
        /// Nested under Plan accordion — shelves only.
        case embedded
        /// Creator You destination — shelves only, no admin chrome.
        case you
    }

    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var editingReviewItem: IntelligenceItem?
    var presentation: Presentation = .standalone

    var body: some View {
        Group {
            switch presentation {
            case .standalone:
                ZStack {
                    chrome.paper.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: MCOSpace.l) {
                            header
                            referencesBody
                        }
                        .padding(.horizontal, MCOSpace.l)
                        .padding(.top, MCOSpace.l)
                        .padding(.bottom, 84)
                    }
                }
                .navigationBarHidden(true)
            case .embedded, .you:
                VStack(alignment: .leading, spacing: MCOSpace.l) {
                    referencesBody
                }
            }
        }
        .sheet(item: $editingReviewItem) { item in
            ReferenceReviewEditSheet(
                item: item,
                isSaving: services.isReviewingReference
            ) { edit in
                review(item, action: .edit, edit: edit)
            }
        }
    }

    @ViewBuilder
    private var referencesBody: some View {
        ActionFeedbackBanner(message: services.lastActionMessage, tone: .info)
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
        NavigationLink {
            referenceImportDestination
        } label: {
            ReferenceImportEntryBlock(isLiveRuntime: services.isLiveSupabaseRuntime)
        }
        .buttonStyle(.plain)
        .disabled(!services.isLiveSupabaseRuntime)
        GrowthReferenceShelf(references: services.intelligenceHome.growthReferences)
        SourcePulseShelf(sourcePulse: services.intelligenceHome.sourcePulse)
        IntelligenceShelf(
            title: "Recently used",
            items: services.intelligenceHome.recentlyUsed
        )
        LibraryNavigationShelf(sections: services.intelligenceHome.librarySections)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Spacer()

                NavigationLink {
                    referenceImportDestination
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(services.isLiveSupabaseRuntime ? chrome.ink : chrome.inkMuted)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(!services.isLiveSupabaseRuntime)
                .accessibilityLabel("Open Reference Import")

                FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                    appState.activeMode = .creator
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("References")
                    .font(MCOType.display)
                    .foregroundStyle(chrome.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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
            let url = URL(string: sourceURL),
            url.scheme != nil,
            url.host != nil
        else {
            services.lastActionMessage = "No valid source link is available for this reference."
            return
        }

        openURL(url)
    }
}

struct ReferenceImportEntryBlock: View {
    @Environment(\.chromePalette) private var chrome
    let isLiveRuntime: Bool

    var body: some View {
        JournalBlock {
            HStack(alignment: .center, spacing: MCOSpace.m) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isLiveRuntime ? chrome.accent : chrome.inkMuted)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Import inspiration")
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(chrome.ink)
                    Text(isLiveRuntime ? "Paste links, handles, notes, or upload CSV." : "Connect live Supabase to import references.")
                        .font(MCOType.caption)
                        .foregroundStyle(chrome.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MCOSpace.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.inkMuted)
            }
        }
    }
}

struct GrowthReferenceShelf: View {
    @Environment(\.chromePalette) private var chrome
    let references: [GrowthReference]

    var body: some View {
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                ShelfHeader(title: "Growth References", trailing: "\(references.count) active")

                VStack(spacing: 0) {
                    ForEach(references) { reference in
                        NavigationLink {
                            GrowthReferenceDetailView(reference: reference)
                        } label: {
                            GrowthReferenceRow(reference: reference)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }
            }
        }
    }
}

struct GrowthReferenceRow: View {
    @Environment(\.chromePalette) private var chrome
    let reference: GrowthReference

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: reference.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(chrome.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(reference.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(chrome.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(reference.summary)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.xs) {
                Text(reference.relevanceLabel)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.inkMuted)
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.vertical, MCOSpace.s)
        .accessibilityElement(children: .combine)
    }
}

struct GrowthReferenceDetailView: View {
    @Environment(\.chromePalette) private var chrome
    @Environment(\.openURL) private var openURL
    let reference: GrowthReference

    var body: some View {
        ChromeScreen(bottomContentPadding: MCOSpace.xl, showsBottomBar: false) {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                summaryBlock
                hookBlock
                usageBlock
                sourcesBlock
            }
        } bottomBar: {
            EmptyView()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack(alignment: .center, spacing: MCOSpace.s) {
                Image(systemName: reference.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(chrome.accent)
                    .frame(width: 38, height: 38)
                    .background(chrome.paperRaised.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                            .stroke(chrome.hairline, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Growth Reference")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(chrome.accent)
                    Text(reference.title)
                        .font(MCOType.screenTitle)
                        .foregroundStyle(chrome.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summaryBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(spacing: MCOSpace.s) {
                    StatusChip(text: reference.relevanceLabel, tone: .ready)
                    ForEach(reference.tags.prefix(2), id: \.self) { tag in
                        StatusChip(text: tag, tone: .quiet)
                    }
                }

                Text(reference.summary)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(chrome.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reference.whyItWorks)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hookBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Hook formulas")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    ForEach(reference.hookFormulas, id: \.self) { hook in
                        ReferenceDetailLine(title: "Hook", value: hook)
                    }
                }
            }
        }
    }

    private var usageBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("When to use")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)
                ForEach(reference.useWhen, id: \.self) { line in
                    Text("- \(line)")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(chrome.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ReferenceDetailLine(title: "Creator idea", value: reference.sampleCreatorIdea)
            }
        }
    }

    private var sourcesBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                Text("Sources")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)
                ForEach(reference.sourceURLs, id: \.self) { source in
                    Button {
                        if let url = URL(string: source) {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: MCOSpace.s) {
                            Text(source)
                                .font(MCOType.caption)
                                .foregroundStyle(chrome.inkMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: MCOSpace.s)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(chrome.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SourcePulseShelf: View {
    @Environment(\.chromePalette) private var chrome
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
    @Environment(\.chromePalette) private var chrome
    let reference: ReferenceSummary

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: reference.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(reference.state.accentColor(using: chrome))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(reference.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(chrome.ink)
                    .lineLimit(1)
                Text("\(reference.sourceType) - \(reference.note)")
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            StatusChip(text: reference.state.label, tone: reference.state.tone)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct NeedsYourCallShelf: View {
    @Environment(\.chromePalette) private var chrome
    let items: [IntelligenceItem]
    let isReviewing: Bool
    let onApprove: (IntelligenceItem) -> Void
    let onDismiss: (IntelligenceItem) -> Void
    let onEdit: (IntelligenceItem) -> Void
    let onOpen: (IntelligenceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "Needs your call", trailing: "\(items.count)")

            if !items.isEmpty {
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
    @Environment(\.chromePalette) private var chrome
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
                        .foregroundStyle(item.state.accentColor(using: chrome))
                        .frame(width: 34, alignment: .leading)
                }
                .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(chrome.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    Text(item.subtitle)
                        .font(MCOType.caption)
                        .foregroundStyle(chrome.inkMuted)
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
    @Environment(\.chromePalette) private var chrome
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
        .foregroundStyle(isDisabled ? chrome.inkMuted : chrome.accent)
        .background(chrome.paperRaised.opacity(isDisabled ? 0.36 : 0.78))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(chrome.hairline, lineWidth: 1)
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct IntelligenceShelf: View {
    @Environment(\.chromePalette) private var chrome
    let title: String
    let items: [IntelligenceItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                ShelfHeader(title: title, trailing: nil)

                VStack(spacing: 0) {
                    ForEach(items) { item in
                        NavigationLink {
                            ReferenceItemDetailView(item: item)
                        } label: {
                            IntelligenceShelfRow(item: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }
            }
        }
    }
}

struct IntelligenceShelfRow: View {
    @Environment(\.chromePalette) private var chrome
    let item: IntelligenceItem

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(item.state.accentColor(using: chrome))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(item.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(chrome.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(item.kind.rawValue)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.xs) {
                Text(item.trailingNote)
                    .font(MCOType.caption)
                    .foregroundStyle(item.state.accentColor(using: chrome))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.inkMuted)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, MCOSpace.s)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryNavigationShelf: View {
    @Environment(\.chromePalette) private var chrome
    let sections: [IntelligenceLibrarySection]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "Library", trailing: "Counts stay secondary.")

            VStack(spacing: 0) {
                ForEach(sections) { section in
                    NavigationLink {
                        ReferenceLibrarySectionDetailView(section: section)
                    } label: {
                        LibraryNavigationRow(section: section)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }
}

struct LibraryNavigationRow: View {
    @Environment(\.chromePalette) private var chrome
    let section: IntelligenceLibrarySection

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: section.symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(chrome.inkMuted)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(section.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(chrome.ink)
                Text(section.subtitle)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            HStack(spacing: MCOSpace.s) {
                Text("\(section.count)")
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.inkMuted)
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct ReferenceItemDetailView: View {
    @Environment(\.chromePalette) private var chrome
    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services
    let item: IntelligenceItem

    var body: some View {
        ChromeScreen(bottomContentPadding: MCOSpace.xl, showsBottomBar: false) {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                ActionFeedbackBanner(message: services.lastActionMessage, tone: .info)
                summaryBlock
                detailBlock
                sourceBlock
            }
        } bottomBar: {
            EmptyView()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack(alignment: .center, spacing: MCOSpace.s) {
                Image(systemName: item.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(item.state.accentColor(using: chrome))
                    .frame(width: 38, height: 38)
                    .background(chrome.paperRaised.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                            .stroke(chrome.hairline, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(item.kind.rawValue)
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(chrome.accent)
                    Text(item.title)
                        .font(MCOType.screenTitle)
                        .foregroundStyle(chrome.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summaryBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(spacing: MCOSpace.s) {
                    StatusChip(text: item.state.label, tone: item.state.tone)
                    StatusChip(text: item.trailingNote, tone: item.state == .needsReview ? .warning : .quiet)
                    if let typeChip = item.typeChip {
                        ReferenceImportTypeChipView(typeChip: typeChip)
                    }
                }

                Text(item.subtitle)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(chrome.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("How this should be used")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)
                Text(usageGuidance)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(chrome.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let sortKey = item.sortKey?.nilIfBlank {
                    ReferenceDetailLine(title: "Priority signal", value: sortKey)
                }
            }
        }
    }

    private var sourceBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                Text("Source")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)

                if let sourceURL = item.sourceURL?.nilIfBlank {
                    Text(sourceURL)
                        .font(MCOType.caption)
                        .foregroundStyle(chrome.inkMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No source link attached.")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(chrome.inkMuted)
                }

                PrimaryActionButton(title: "Open source", systemImage: "arrow.up.right") {
                    openSource()
                }
                .disabled(item.sourceURL?.nilIfBlank == nil)
                .opacity(item.sourceURL?.nilIfBlank == nil ? 0.52 : 1)
            }
        }
    }

    private var usageGuidance: String {
        switch item.kind {
        case .pattern:
            "Use this as a repeatable content structure when drafting weekly cards. It should shape framing, not override the weekly brief."
        case .trend:
            "Use this as context for a timely angle. Keep it grounded in the creator's current week before using it."
        case .audio:
            "Use this as an optional audio direction for Reels. If it does not fit the daily card, keep the card shootable without it."
        case .idea:
            "Use this as a candidate card idea. It still needs to fit the selected week, creator profile, and daily energy."
        case .watchlist:
            "Use this as a source to monitor. Pull from it when it gives a practical angle for the creator's week."
        }
    }

    private func openSource() {
        guard
            let sourceURL = item.sourceURL,
            let url = URL(string: sourceURL),
            url.scheme != nil,
            url.host != nil
        else {
            services.lastActionMessage = "No valid source link is available for this reference."
            return
        }

        openURL(url)
    }
}

struct ReferenceLibrarySectionDetailView: View {
    @Environment(\.chromePalette) private var chrome
    let section: IntelligenceLibrarySection

    var body: some View {
        ChromeScreen(bottomContentPadding: MCOSpace.xl, showsBottomBar: false) {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                JournalBlock {
                    VStack(alignment: .leading, spacing: MCOSpace.m) {
                        ReferenceDetailLine(title: "Saved references", value: "\(section.count)")
                        ReferenceDetailLine(title: "Scope", value: section.subtitle)
                    }
                }
                JournalBlock {
                    VStack(alignment: .leading, spacing: MCOSpace.s) {
                        Text("What belongs here")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(chrome.accent)
                        Text("This section groups references that can inform daily content generation. The next useful layer is a filtered list of all saved references in this bucket.")
                            .font(MCOType.bodySmall)
                            .foregroundStyle(chrome.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } bottomBar: {
            EmptyView()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: section.symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(chrome.accentSecondary)
                .frame(width: 42, height: 42)
                .background(chrome.paperRaised.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                        .stroke(chrome.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Reference Library")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(chrome.accent)
                Text(section.title)
                    .font(MCOType.screenTitle)
                    .foregroundStyle(chrome.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ReferenceDetailLine: View {
    @Environment(\.chromePalette) private var chrome
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(chrome.inkMuted)
            Text(value)
                .font(MCOType.bodySmall)
                .foregroundStyle(chrome.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShelfHeader: View {
    @Environment(\.chromePalette) private var chrome
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(MCOType.tinyLabel)
                .foregroundStyle(chrome.accent)
            Spacer(minLength: MCOSpace.s)
            if let trailing {
                Text(trailing)
                    .font(MCOType.caption)
                    .foregroundStyle(chrome.inkMuted)
                    .lineLimit(1)
            }
        }
    }
}

extension IntelligenceReviewState {
    func accentColor(using palette: ChromePalette) -> Color {
        switch self {
        case .ready, .approved:
            palette.statusPositive
        case .needsReview:
            palette.accentSecondary
        case .usedThisWeek:
            palette.inkMuted
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
