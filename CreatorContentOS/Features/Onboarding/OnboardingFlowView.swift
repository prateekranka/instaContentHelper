import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: OnboardingFocusField?

    var onSoftSkip: () -> Void
    var onHandoffComplete: (OnboardingFirstIdeaHandoffResult, OnboardingFirstDayHandoff) -> Void

    private enum OnboardingFocusField: Hashable {
        case customSubject
        case context(String)
        case creatorNote
    }

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    progressHeader
                    stepContent
                        .padding(.horizontal, PocketSheetSpace.l)
                        .padding(.top, PocketSheetSpace.m)
                        .padding(.bottom, model.step == .review ? 160 : PocketSheetSpace.l)
                }
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.toastMessage)
        .accessibilityIdentifier("onboarding.flow")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .interests:
            interestsStep
        case .tasteExamples:
            tasteExamplesStep
        case .productionConstraints:
            productionConstraintsStep
        case .interestContext:
            interestContextStep
        case .review:
            reviewStep
        }
    }

    // MARK: - Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            OnboardingProgressBar(
                currentStep: model.step.rawValue,
                totalSteps: OnboardingStep.allCases.count
            )
            .padding(.horizontal, PocketSheetSpace.l)
            .accessibilityIdentifier("onboarding.stepIndicator")

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text(stepTitle)
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(stepSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.top, PocketSheetSpace.xs)
        }
        .padding(.top, PocketSheetSpace.l)
    }

    private var stepTitle: String {
        switch model.step {
        case .interests: "Let's get to know you"
        case .tasteExamples: "Which of these could you imagine posting?"
        case .productionConstraints: "What can you comfortably create?"
        case .interestContext: "A bit more about you"
        case .review: "Here's what we've understood"
        }
    }

    private var stepSubtitle: String {
        switch model.step {
        case .interests:
            "What would you enjoy making content about? (Pick as many as you like)"
        case .tasteExamples:
            "Pick what feels most like you (no right or wrong answer)."
        case .productionConstraints:
            "Select all that work for you."
        case .interestContext:
            "These help us make ideas that feel personal and relevant."
        case .review:
            "You can edit anything."
        }
    }

    // MARK: - Step 1: Interests

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            HStack(spacing: PocketSheetSpace.xs) {
                ForEach(OnboardingStartingPoint.allCases, id: \.self) { point in
                    OnboardingStartingPointChip(
                        point: point,
                        isSelected: model.startingPoint == point
                    ) {
                        model.setStartingPoint(point)
                    }
                    .accessibilityIdentifier("onboarding.startingPoint.\(point.rawValue)")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: PocketSheetSpace.xs)],
                spacing: PocketSheetSpace.xs
            ) {
                ForEach(OnboardingInterestCatalog.starter) { interest in
                    OnboardingInterestChip(
                        label: interest.label,
                        isSelected: model.interestIDs.contains(interest.id)
                    ) {
                        model.toggleInterest(interest.id)
                    }
                    .accessibilityIdentifier("onboarding.interest.\(interest.id)")
                }
            }

            if !model.customSubjects.isEmpty {
                FlowLayout(spacing: PocketSheetSpace.xs) {
                    ForEach(model.customSubjects, id: \.self) { subject in
                        OnboardingCustomSubjectTag(subject: subject) {
                            model.removeCustomSubject(subject)
                        }
                    }
                }
            }

            TextField("Or tell us in your own words…", text: $model.customSubjectDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(PocketSheetSpace.s)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
                .focused($focusedField, equals: .customSubject)
                .submitLabel(.done)
                .onSubmit { model.addCustomSubject() }
                .accessibilityIdentifier("onboarding.customSubject")
        }
    }

    // MARK: - Step 2: Taste

    private var tasteExamplesStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            ForEach(model.displayedTasteExamples) { example in
                tasteExampleCard(example)
            }

            Button {
                model.refreshTasteExamples()
            } label: {
                Text("None of these — show different examples")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.taste.refresh")
        }
    }

    private func tasteExampleCard(_ example: OnboardingTasteExample) -> some View {
        let selected = model.selectedTasteExampleIDs.contains(example.id)
        return Button {
            model.toggleTasteExample(example.id)
        } label: {
            HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(example.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: PocketSheetSpace.s)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.inkQuiet)
            }
            .padding(PocketSheetSpace.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? OnboardingTheme.selectionFill : PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(
                        selected ? OnboardingTheme.selectionStroke : PocketSheetTheme.Color.hairline,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.taste.\(example.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Step 3: Production

    private var productionConstraintsStep: some View {
        OnboardingProductionForm(
            formats: Binding(
                get: { model.formats },
                set: { model.formats = $0; model.persistProgress() }
            ),
            timeToCreate: Binding(
                get: { model.timeToCreate },
                set: { model.timeToCreate = $0; model.persistProgress() }
            ),
            contentLanguage: Binding(
                get: { model.contentLanguage },
                set: { model.updateContentLanguage($0) }
            ),
            showFace: Binding(
                get: { model.showFace },
                set: { model.showFace = $0; model.persistProgress() }
            ),
            useVoice: Binding(
                get: { model.useVoice },
                set: { model.useVoice = $0; model.persistProgress() }
            )
        )
    }

    // MARK: - Step 4: Context

    private var interestContextStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            ForEach(model.promptedContextQuestions) { question in
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text(question.prompt)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    TextField(question.placeholder, text: Binding(
                        get: { model.contextAnswers[question.id, default: ""] },
                        set: { model.updateContextAnswer(questionID: question.id, answer: $0) }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(PocketSheetSpace.s)
                    .background(PocketSheetTheme.Color.paperRaised)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                            .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                    }
                    .focused($focusedField, equals: .context(question.id))
                    .accessibilityIdentifier(question.accessibilityIdentifier)
                }
            }

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Anything else you want to share? (Optional)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                TextField("Anything you'd like us to keep in mind…", text: Binding(
                    get: { model.creatorNote },
                    set: { model.updateCreatorNote($0) }
                ), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(PocketSheetSpace.s)
                .background(PocketSheetTheme.Color.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
                .focused($focusedField, equals: .creatorNote)
                .accessibilityIdentifier("onboarding.creatorNote")
            }
        }
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            if model.isConfirmingFirstIdea {
                HStack(spacing: PocketSheetSpace.s) {
                    ProgressView()
                        .tint(PocketSheetTheme.Color.ink)
                    Text("Preparing your first idea…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("onboarding.preparing")
            }

            PocketSheetFeedbackBanner(message: model.confirmErrorMessage, kind: .neutral)

            summaryBlock(title: "Your interests", editStep: .interests) {
                FlowLayout(spacing: PocketSheetSpace.xs) {
                    ForEach(model.interestDisplayLabels, id: \.self) { label in
                        PocketSheetChip(text: label, isEmphasized: true)
                    }
                }
            }

            if let starting = model.startingPoint {
                summaryBlock(title: "Starting point", editStep: .interests) {
                    Text(starting.displayLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                }
            }

            summaryBlock(title: "Your style", editStep: .tasteExamples) {
                Text(OnboardingReviewSummary.stylePhrase(
                    selectedExamples: model.displayedTasteExamples.filter {
                        model.selectedTasteExampleIDs.contains($0.id)
                    },
                    formats: model.formats
                ))
                .font(.system(size: 14))
                .foregroundStyle(PocketSheetTheme.Color.ink)
            }

            summaryBlock(title: "Your formats", editStep: .productionConstraints) {
                Text(model.formats.map(\.displayLabel).joined(separator: ", "))
                    .font(.system(size: 14))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
            }

            summaryBlock(title: "Your time", editStep: .productionConstraints) {
                Text(OnboardingReviewSummary.timeLabel(model.timeToCreate))
                    .font(.system(size: 14))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
            }

            summaryBlock(title: "Language & camera", editStep: .productionConstraints) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(model.contentLanguage)
                    Text(OnboardingReviewSummary.faceVoiceLabel(showFace: model.showFace, useVoice: model.useVoice))
                }
                .font(.system(size: 14))
                .foregroundStyle(PocketSheetTheme.Color.ink)
            }

            let contextLines = model.promptedContextQuestions.compactMap { question -> String? in
                let answer = model.contextAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return answer.isEmpty ? nil : answer
            }
            if !contextLines.isEmpty || model.creatorNote.nilIfBlank != nil {
                summaryBlock(title: "Recent interests", editStep: .interestContext) {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        ForEach(contextLines, id: \.self) { line in
                            Text(line)
                        }
                        if let note = model.creatorNote.nilIfBlank {
                            Text(note)
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
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
                    .frame(minHeight: 44)
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
            case .interests:
                skipLink
                continueButton(
                    title: "Continue",
                    enabled: model.interestsContinueEnabled,
                    identifier: "onboarding.continue.interests"
                ) {
                    model.advanceFromInterests()
                }

            case .tasteExamples:
                if model.step.rawValue > 0 {
                    backButton
                }
                continueButton(
                    title: "Continue",
                    enabled: model.tasteContinueEnabled,
                    identifier: "onboarding.continue.taste"
                ) {
                    model.advanceFromTasteExamples()
                }

            case .productionConstraints:
                backButton
                continueButton(
                    title: "Continue",
                    enabled: model.productionContinueEnabled,
                    identifier: "onboarding.continue.production"
                ) {
                    model.advanceFromProductionConstraints()
                }

            case .interestContext:
                backButton
                Button("Nothing specific right now") {
                    model.skipContextStep()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .frame(minHeight: 44)
                .accessibilityIdentifier("onboarding.context.skip")
                continueButton(
                    title: "Continue",
                    enabled: model.contextContinueEnabled,
                    identifier: "onboarding.continue.context"
                ) {
                    model.advanceFromInterestContext()
                }

            case .review:
                backButton
                if case .generationFailed = model.confirmState {
                    PocketSheetPrimaryAction(title: "Retry") {
                        Task { await confirmFirstIdea() }
                    }
                    .accessibilityIdentifier("onboarding.retryFirstIdea")
                } else {
                    PocketSheetPrimaryAction(title: "Show my first idea") {
                        Task { await confirmFirstIdea() }
                    }
                    .disabled(model.isConfirmingFirstIdea)
                    .opacity(model.isConfirmingFirstIdea ? 0.48 : 1)
                    .accessibilityIdentifier("onboarding.generateFirstDay")
                }
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.bottom, PocketSheetSpace.l)
        .background(PocketSheetTheme.Color.paper)
    }

    private var backButton: some View {
        PocketSheetSecondaryAction(title: "Back") {
            model.goBack()
        }
        .accessibilityIdentifier("onboarding.back")
    }

    private func continueButton(
        title: String,
        enabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        PocketSheetPrimaryAction(title: title, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.48)
            .accessibilityIdentifier(identifier)
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

    private func confirmFirstIdea() async {
        let handoff = model.finishAndGenerateFirstDay(todayDate: services.currentTodayDateString)
        let result = await model.confirmFirstIdea(
            services: services,
            scheduledDate: handoff.scheduledDate
        )
        onHandoffComplete(result, handoff)
    }
}

// MARK: - Progress bar

private struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? OnboardingTheme.progressFill : OnboardingTheme.progressTrack)
                    .frame(height: 3)
            }
        }
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
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

// MARK: - Flow layout

private struct FlowLayout: Layout {
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
