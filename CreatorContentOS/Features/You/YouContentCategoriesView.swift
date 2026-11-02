import SwiftUI

struct YouContentCategoriesView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    @State private var selection = YouInterestsSelection(interestIDs: [], customSubjects: [], startingPoint: nil)
    @State private var customSubjectDraft = ""
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        YouDestinationScaffold(
            title: "Interests & style",
            subtitle: "Topics and starting point that shape your daily ideas.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                PocketSheetBlock(header: "Starting point") {
                    VStack(spacing: 0) {
                        ForEach(OnboardingStartingPoint.allCases, id: \.self) { point in
                            Button {
                                selection.setStartingPoint(point)
                                scheduleSave()
                            } label: {
                                PocketSheetRow(
                                    title: point.displayLabel,
                                    trailingSymbol: selection.startingPoint == point ? "checkmark.circle.fill" : "circle",
                                    leadingSymbol: point == .justStarting ? "sparkles" : "arrow.up.right"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(point.displayLabel)
                            .accessibilityAddTraits(selection.startingPoint == point ? .isSelected : [])
                            .accessibilityIdentifier("you.interests.startingPoint.\(point.rawValue)")
                            if point != OnboardingStartingPoint.allCases.last {
                                PocketSheetDivider()
                            }
                        }
                    }
                }
                PocketSheetBlock {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                        Text("Pick as many as you like. Custom topics are welcome.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, PocketSheetSpace.l)
                            .padding(.top, PocketSheetSpace.s)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 112), spacing: PocketSheetSpace.s)],
                            spacing: PocketSheetSpace.s
                        ) {
                            ForEach(OnboardingInterestCatalog.starter) { interest in
                                interestChip(interest)
                                    .accessibilityIdentifier("you.interests.chip.\(interest.id)")
                            }
                        }
                        .padding(.horizontal, PocketSheetSpace.l)

                        if !selection.customSubjects.isEmpty {
                            YouFlowLayout(spacing: PocketSheetSpace.xs) {
                                ForEach(selection.customSubjects, id: \.self) { subject in
                                    customSubjectTag(subject) {
                                        selection.removeCustomSubject(subject)
                                        scheduleSave()
                                    }
                                }
                            }
                            .padding(.horizontal, PocketSheetSpace.l)
                        }

                        TextField("Or tell us in your own words…", text: $customSubjectDraft)
                            .font(PocketSheetType.bodyText)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .padding(PocketSheetSpace.m)
                            .background(PocketSheetTheme.Color.paper)
                            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                            }
                            .padding(.horizontal, PocketSheetSpace.l)
                            .accessibilityIdentifier("you.interests.customInput")
                            .submitLabel(.done)
                            .onSubmit { addCustomSubject() }

                        statusLine
                            .padding(.horizontal, PocketSheetSpace.l)
                            .padding(.bottom, PocketSheetSpace.s)
                    }
                }
            }
        }
        .accessibilityIdentifier("you.screen.interests")
        .onAppear {
            guard !didLoad else { return }
            selection = YouInterestsSelection.from(profile: services.creatorProfileSummary)
            didLoad = true
        }
        .onChange(of: services.creatorProfileSummary.contentPillars) { _, _ in
            reloadIfNeeded()
        }
        .onChange(of: services.creatorProfileSummary.customSubjects) { _, _ in
            reloadIfNeeded()
        }
        .onChange(of: services.creatorProfileSummary.startingPoint) { _, _ in
            reloadIfNeeded()
        }
    }

    private func interestChip(_ interest: OnboardingInterestOption) -> some View {
        let selected = selection.interestIDs.contains(interest.id)
        return Button {
            selection.toggleInterest(interest.id)
            scheduleSave()
        } label: {
            HStack(spacing: 0) {
                Text(interest.label)
                    .padding(.horizontal, PocketSheetSpace.xxs)
                    .fixedSize(horizontal: false, vertical: true)
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .font(PocketSheetType.actionSecondary)
            .foregroundStyle(selected ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.xxs)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.paperRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(interest.label)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func customSubjectTag(_ subject: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Text(subject)
                .font(PocketSheetType.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(PocketSheetType.navIcon)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(subject)")
        }
        .foregroundStyle(PocketSheetTheme.Color.ink)
        .padding(.leading, PocketSheetSpace.m)
        .background(PocketSheetTheme.Color.paperRaised, in: Capsule())
    }

    @ViewBuilder
    private var statusLine: some View {
        if services.isSavingCreatorProfile {
            Text("Saving…")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        } else if let error = services.creatorProfileEditError {
            Text(error)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
        } else {
            Text("Changes save automatically and shape future ideas.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private func addCustomSubject() {
        selection.addCustomSubject(customSubjectDraft)
        customSubjectDraft = ""
        scheduleSave()
    }

    private func reloadIfNeeded() {
        let incoming = YouInterestsSelection.from(profile: services.creatorProfileSummary)
        if incoming.resolvedContentPillars() == selection.resolvedContentPillars(),
           incoming.startingPoint == selection.startingPoint {
            return
        }
        selection = incoming
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard selection.isValid else { return }

        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await persistSelection()
        }
    }

    @MainActor
    private func persistSelection() async {
        guard selection.isValid else { return }
        let update = selection.profileUpdate(base: services.creatorProfileSummary)
        _ = await services.updateCreatorProfileImmediately(update)
    }
}

/// Simple flow layout for You custom subject tags.
private struct YouFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
