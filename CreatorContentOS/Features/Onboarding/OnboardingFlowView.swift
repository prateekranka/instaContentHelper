import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reelDraft = ""
    @State private var profileDraft = ""
    @FocusState private var focusedReferenceField: OnboardingReferenceInputKind?

    var onSoftSkip: () -> Void
    var onComplete: (OnboardingFirstDayHandoff) -> Void

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    stepContent
                        .padding(.horizontal, PocketSheetSpace.l)
                        .padding(.top, PocketSheetSpace.m)
                }
                .padding(.bottom, PocketSheetSpace.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dock
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toastMessage {
                OnboardingToast(message: toast)
                    .padding(.bottom, 120)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            if model.toastMessage == toast {
                                model.toastMessage = nil
                            }
                        }
                    }
            }
        }
        .animation(.snappy(duration: 0.2), value: model.toastMessage)
        .onAppear {
            configureLiveProfileVerifierIfNeeded()
        }
        .accessibilityIdentifier("onboarding.flow")
    }

    private func configureLiveProfileVerifierIfNeeded() {
        guard services.isLiveSupabaseRuntime else { return }
        model.configureProfileVerifier(AppServicesOnboardingProfileVerifier(services: services))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .categories:
            categoriesStep
        case .references:
            referencesStep
        case .confirm:
            confirmStep
        }
    }

    private var header: some View {
        let centersCategoriesHeader = model.step == .categories
        let centersStepIndicatorOnly = model.step == .references
        return VStack(alignment: centersCategoriesHeader ? .center : .leading, spacing: PocketSheetSpace.xs) {
            Text("Step \(model.step.rawValue + 1) of 3")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                .tracking(0.44)
                .frame(maxWidth: .infinity, alignment: centersStepIndicatorOnly || centersCategoriesHeader ? .center : .leading)
                .accessibilityIdentifier("onboarding.stepIndicator")

            Text(stepTitle)
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityAddTraits(.isHeader)

            Text(stepSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .multilineTextAlignment(centersCategoriesHeader ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: centersCategoriesHeader ? .center : .leading)
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.top, PocketSheetSpace.l)
    }

    private var stepTitle: String {
        switch model.step {
        case .categories: "What do you create about?"
        case .references: "Who should we learn from?"
        case .confirm: "Ready to generate?"
        }
    }

    private var stepSubtitle: String {
        switch model.step {
        case .categories:
            "Pick your content categories — you can always change these later in You."
        case .references:
            "Reels and profiles teach us your aesthetic."
        case .confirm:
            "Done."
        }
    }

    // MARK: - Categories

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            Text("Pick 1–3")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: PocketSheetSpace.xs)],
                spacing: PocketSheetSpace.xs
            ) {
                ForEach(OnboardingCategories.starter) { category in
                    categoryChip(id: category.id, label: category.label)
                }
                categoryChip(id: OnboardingCategories.otherID, label: "Other")
            }

            if model.selectedCategoryIDs.contains(OnboardingCategories.otherID) {
                TextField("Your category…", text: Binding(
                    get: { model.categoryOtherText },
                    set: { model.updateCategoryOther($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(PocketSheetSpace.s)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
                .accessibilityIdentifier("onboarding.categoryOther")
            }
        }
    }

    private func categoryChip(id: String, label: String) -> some View {
        let selected = model.selectedCategoryIDs.contains(id)
        return Button {
            model.toggleCategory(id)
        } label: {
            Text(label)
                .font(PocketSheetType.chip)
                .foregroundStyle(selected ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)
                .background(selected ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.fillMuted)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(
                        selected ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.hairline,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.category.\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - References

    @ViewBuilder
    private var referencesStep: some View {
        let attn = model.referenceValidation
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            referenceFieldSection(
                title: "Reel URL",
                placeholder: "https://instagram.com/reel/…",
                draft: $reelDraft,
                kind: .reel,
                showAttention: attn.reel,
                addTitle: "+ Add reel",
                isAddDisabled: false
            )

            referenceFieldSection(
                title: "Profile @handle",
                placeholder: "@creator",
                draft: $profileDraft,
                kind: .profile,
                showAttention: attn.profile,
                addTitle: model.isVerifyingProfile ? "Checking on Instagram…" : "+ Add profile",
                isAddDisabled: model.isVerifyingProfile
            )

            if model.references.isEmpty {
                Text("No references yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.references) { ref in
                        HStack {
                            Text(ref.listDisplayLabel)
                                .font(.system(size: 14))
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            Spacer(minLength: PocketSheetSpace.s)
                            Button {
                                model.removeReference(id: ref.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .accessibilityLabel("Remove reference")
                        }
                        .padding(.vertical, PocketSheetSpace.xs)
                        if ref.id != model.references.last?.id {
                            PocketSheetDivider()
                        }
                    }
                }
            }

            Text("\(model.references.count)/10 · \(OnboardingValidation.reelCount(in: model.references)) reel · \(OnboardingValidation.profileCount(in: model.references)) profile")
                .font(.system(size: 12))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)

            if let hint = model.displayedReferenceHint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        model.referenceValidationMessage != nil
                            ? PocketSheetTheme.Color.validationAttention
                            : PocketSheetTheme.Color.inkMuted
                    )
                    .accessibilityIdentifier("onboarding.refHint")
                    .accessibilityAddTraits(model.referenceValidationMessage != nil ? .isStaticText : [])
            }
        }
        .onChange(of: reelDraft) { _, newValue in
            model.reelDraftText = newValue
        }
        .onChange(of: profileDraft) { _, newValue in
            model.profileDraftText = newValue
        }
        .onChange(of: model.reelDraftText) { _, newValue in
            if newValue != reelDraft {
                reelDraft = newValue
            }
        }
        .onChange(of: model.profileDraftText) { _, newValue in
            if newValue != profileDraft {
                profileDraft = newValue
            }
        }
        .onChange(of: model.step) { _, newStep in
            if newStep == .references {
                reelDraft = model.reelDraftText
                profileDraft = model.profileDraftText
            }
        }
    }

    private func referenceFieldSection(
        title: String,
        placeholder: String,
        draft: Binding<String>,
        kind: OnboardingReferenceInputKind,
        showAttention: Bool,
        addTitle: String,
        isAddDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)

            ZStack(alignment: .topLeading) {
                TextField("", text: draft, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 15))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .focused($focusedReferenceField, equals: kind)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("onboarding.refInput.\(kind.rawValue)")
                    .accessibilityLabel(placeholder)

                if draft.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .padding(PocketSheetSpace.xs)
                }
            }
            .frame(minHeight: 52)
            .padding(PocketSheetSpace.xs)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(
                        showAttention ? PocketSheetTheme.Color.validationAttention : PocketSheetTheme.Color.hairline,
                        lineWidth: showAttention ? 2 : 1
                    )
            }
            .onboardingAttentionShake(
                active: showAttention && model.referenceValidation.motion,
                reduceMotion: reduceMotion
            ) {
                model.consumeReferenceAttentionMotionIfNeeded()
            }

            Button {
                switch kind {
                case .reel:
                    model.reelDraftText = draft.wrappedValue
                    focusedReferenceField = .profile
                case .profile:
                    model.profileDraftText = draft.wrappedValue
                }
                Task { await model.addReference(from: draft.wrappedValue, kind: kind) }
            } label: {
                Text(addTitle)
                    .font(PocketSheetType.actionSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .background(PocketSheetTheme.Color.fillMuted)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAddDisabled)
            .accessibilityIdentifier(kind == .reel ? "onboarding.refAdd.reel" : "onboarding.refAdd.profile")
        }
    }

    // MARK: - Confirm

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            summaryBlock(title: "Categories", editStep: .categories) {
                FlowLayout(spacing: PocketSheetSpace.xs) {
                    ForEach(model.categoryDisplayLabels, id: \.self) { label in
                        PocketSheetChip(text: label, isEmphasized: true)
                    }
                }
            }

            summaryBlock(title: "References (\(model.references.count))", editStep: .references) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    ForEach(model.references) { ref in
                        Text(ref.listDisplayLabel)
                            .font(.system(size: 14))
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    }
                }
            }
        }
    }

    private func summaryBlock<Content: View>(
        title: String,
        editStep: OnboardingStep,
        @ViewBuilder content: () -> Content
    ) -> some View {
        PocketSheetBlock {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                HStack {
                    Text(title)
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Spacer(minLength: PocketSheetSpace.s)
                    Button("Edit") {
                        model.goToStep(editStep)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityIdentifier("onboarding.edit.\(editStep.rawValue)")
                }
                content()
            }
            .padding(PocketSheetSpace.m)
        }
    }

    // MARK: - Dock

    @ViewBuilder
    private var dock: some View {
        VStack(spacing: PocketSheetSpace.s) {
            switch model.step {
            case .categories:
                skipLink
                PocketSheetPrimaryAction(title: "Continue") {
                    model.advanceFromCategories()
                }
                .disabled(!model.categoriesContinueEnabled)
                .opacity(model.categoriesContinueEnabled ? 1 : 0.48)
                .accessibilityIdentifier("onboarding.continue.categories")

            case .references:
                PocketSheetPrimaryAction(title: "Continue") {
                    model.continueFromReferences(reduceMotion: reduceMotion)
                }
                .accessibilityIdentifier("onboarding.continue.references")

            case .confirm:
                Text("Five ideas are ready in Plan. Voice is prefilled from your references.")
                    .font(.system(size: 13))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .multilineTextAlignment(.center)
                PocketSheetPrimaryAction(title: "Show my ideas") {
                    completeOnboarding()
                }
                .accessibilityIdentifier("onboarding.generateFirstDay")
                PocketSheetSecondaryAction(title: "Back") {
                    model.goToStep(.references)
                }
                .accessibilityIdentifier("onboarding.back.confirm")
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.bottom, PocketSheetSpace.l)
        .background(PocketSheetTheme.Color.paper)
    }

    private var skipLink: some View {
        Button("Set up later") {
            model.softSkip()
            onSoftSkip()
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        .frame(minHeight: 44)
        .accessibilityIdentifier("onboarding.setUpLater")
    }

    private func completeOnboarding() {
        let handoff = model.finishAndGenerateFirstDay(todayDate: services.currentTodayDateString)
        Task {
            await applyCompletedDataToProfile(handoff.completedData)
        }
        onComplete(handoff)
    }

    private func applyCompletedDataToProfile(_ data: OnboardingCompletedData) async {
        var update = CreatorProfileUpdate(summary: services.creatorProfileSummary)
        update.contentPillars = data.categoryLabels
        _ = await services.updateCreatorProfileImmediately(update)

        guard services.isLiveSupabaseRuntime, !data.references.isEmpty else { return }
        _ = await OnboardingReferenceImporter.live(services: services).importReferences(data.references)
    }
}

// MARK: - Toast

private struct OnboardingToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.s)
            .background(PocketSheetTheme.Color.inverseInk.opacity(0.92))
            .clipShape(Capsule())
            .accessibilityIdentifier("onboarding.toast")
    }
}

// MARK: - Attention shake

private struct OnboardingAttentionShakeModifier: ViewModifier {
    let active: Bool
    let reduceMotion: Bool
    let onCycleComplete: () -> Void

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : phase)
            .onChange(of: active) { _, isActive in
                guard isActive, !reduceMotion else { return }
                runShakeCycle()
            }
    }

    private func runShakeCycle() {
        let steps: [CGFloat] = [0, -6, 6, -4, 4, 0]
        var delay = 0.0
        for (index, offset) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: 0.06)) {
                    phase = offset
                }
                if index == steps.count - 1 {
                    onCycleComplete()
                }
            }
            delay += 0.06
        }
    }
}

private extension View {
    func onboardingAttentionShake(
        active: Bool,
        reduceMotion: Bool,
        onCycleComplete: @escaping () -> Void
    ) -> some View {
        modifier(
            OnboardingAttentionShakeModifier(
                active: active,
                reduceMotion: reduceMotion,
                onCycleComplete: onCycleComplete
            )
        )
    }
}

// MARK: - Flow layout for chips

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
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
