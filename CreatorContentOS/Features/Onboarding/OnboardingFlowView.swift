import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onSoftSkip: () -> Void
    var onHandoffComplete: (OnboardingFirstIdeaHandoffResult, OnboardingFirstDayHandoff) -> Void

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    launchHeader
                    launchChoiceStep
                        .padding(.horizontal, PocketSheetSpace.l)
                        .padding(.top, PocketSheetSpace.m)
                        .padding(.bottom, 160)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                launchDock
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

    // MARK: - Launch-A one screen

    private var launchHeader: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            OnboardingProgressBar(
                currentStep: OnboardingLaunchPresentation.stepIndex,
                totalSteps: OnboardingLaunchPresentation.stepCount
            )
            .padding(.horizontal, PocketSheetSpace.l)
            .accessibilityIdentifier("onboarding.stepIndicator")

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Quick setup")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Pick a starting point or a few topics — or skip and finish later in You.")
                    .font(.system(size: 15))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.top, PocketSheetSpace.xs)
        }
        .padding(.top, PocketSheetSpace.l)
    }

    private var launchChoiceStep: some View {
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

            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("Where are you starting from?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)

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
            }

            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("What would you enjoy making content about?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)

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
            }

            Text("You can add taste, production prefs, and voice anytime under You.")
                .font(.system(size: 13))
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
        }
    }

    // MARK: - Dock

    @ViewBuilder
    private var launchDock: some View {
        VStack(spacing: PocketSheetSpace.s) {
            Button("Set up later") {
                Task { await skipAndPrepareFirstIdea() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            .frame(minHeight: 44)
            .disabled(model.isConfirmingFirstIdea)
            .accessibilityIdentifier("onboarding.setUpLater")

            if case .generationFailed = model.confirmState {
                PocketSheetPrimaryAction(title: "Retry") {
                    Task { await confirmFirstIdea() }
                }
                .accessibilityIdentifier("onboarding.retryFirstIdea")
            } else {
                PocketSheetPrimaryAction(title: "Show my first idea") {
                    Task { await confirmFirstIdea() }
                }
                .disabled(!model.launchContinueEnabled || model.isConfirmingFirstIdea)
                .opacity(model.launchContinueEnabled && !model.isConfirmingFirstIdea ? 1 : 0.48)
                .accessibilityIdentifier("onboarding.generateFirstDay")
            }

            PocketSheetSecondaryAction(title: "Not now") {
                model.cancelSetup()
                onSoftSkip()
            }
            .disabled(model.isConfirmingFirstIdea)
            .accessibilityIdentifier("onboarding.cancel")
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.bottom, PocketSheetSpace.l)
        .background(PocketSheetTheme.Color.paper)
    }

    private func confirmFirstIdea() async {
        let handoff = model.finishAndGenerateFirstDay(todayDate: services.currentTodayDateString)
        let result = await model.confirmFirstIdea(
            services: services,
            scheduledDate: handoff.scheduledDate
        )
        onHandoffComplete(result, handoff)
    }

    private func skipAndPrepareFirstIdea() async {
        model.noteSkippedSetup()
        let handoff = model.finishAndGenerateFirstDay(todayDate: services.currentTodayDateString)
        let result = await model.confirmFirstIdea(
            services: services,
            scheduledDate: handoff.scheduledDate
        )
        switch result {
        case .completed, .skippedExistingReady:
            model.toastMessage = "You can finish setup in You."
        case .persistFailed, .generationFailed:
            break
        }
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
