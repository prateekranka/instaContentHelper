import SwiftUI

/// Shared production-constraints form for onboarding and You preference editing.
struct OnboardingProductionForm: View {
    @Binding var formats: [OnboardingProductionFormat]
    @Binding var timeToCreate: OnboardingTimeToCreate?
    @Binding var contentLanguage: String
    @Binding var showFace: Bool?
    @Binding var useVoice: Bool?
    var identifierPrefix: String = "onboarding"

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                ForEach(OnboardingProductionFormat.allCases) { format in
                    formatRow(format)
                }
            }

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("How much time do you usually have?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text("Time you usually have to film or create, not the length of the finished video.")
                    .font(.system(size: 12))
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PocketSheetSpace.xs) {
                    ForEach(OnboardingTimeToCreate.allCases) { time in
                        timeChip(time)
                    }
                }
            }

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Content language")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                TextField("English", text: $contentLanguage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(PocketSheetSpace.s)
                    .background(PocketSheetTheme.Color.paperRaised)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                            .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                    }
                    .accessibilityIdentifier("\(identifierPrefix).contentLanguage")
            }

            yesNoGroup(
                title: "Are you comfortable showing your face?",
                value: showFace,
                yesAction: { showFace = true },
                noAction: { showFace = false },
                identifierPrefix: "\(identifierPrefix).showFace"
            )

            yesNoGroup(
                title: "Are you comfortable using your voice?",
                value: useVoice,
                yesAction: { useVoice = true },
                noAction: { useVoice = false },
                identifierPrefix: "\(identifierPrefix).useVoice"
            )
        }
    }

    private func formatRow(_ format: OnboardingProductionFormat) -> some View {
        let selected = formats.contains(format)
        return Button {
            toggleFormat(format)
        } label: {
            HStack(spacing: PocketSheetSpace.s) {
                Image(systemName: format.symbolName)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text(format.displayLabel)
                    .font(.system(size: 15))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Spacer(minLength: PocketSheetSpace.s)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.inkQuiet)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, PocketSheetSpace.s)
            .background(selected ? OnboardingTheme.selectionFill.opacity(0.5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifierPrefix).format.\(format.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func timeChip(_ time: OnboardingTimeToCreate) -> some View {
        let selected = timeToCreate == time
        return Button {
            timeToCreate = time
        } label: {
            Text(time.displayLabel)
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .padding(.horizontal, PocketSheetSpace.s)
                .frame(minHeight: 44)
                .background(selected ? OnboardingTheme.selectionFill : PocketSheetTheme.Color.fillMuted)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(
                        selected ? OnboardingTheme.selectionStroke : PocketSheetTheme.Color.hairline,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifierPrefix).time.\(time.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func yesNoGroup(
        title: String,
        value: Bool?,
        yesAction: @escaping () -> Void,
        noAction: @escaping () -> Void,
        identifierPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            HStack(spacing: PocketSheetSpace.xs) {
                yesNoChip(label: "Yes", selected: value == true, action: yesAction)
                    .accessibilityIdentifier("\(identifierPrefix).yes")
                yesNoChip(label: "No", selected: value == false, action: noAction)
                    .accessibilityIdentifier("\(identifierPrefix).no")
            }
        }
    }

    private func yesNoChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(PocketSheetType.chip)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .padding(.horizontal, PocketSheetSpace.m)
                .frame(minHeight: 44)
                .background(selected ? OnboardingTheme.selectionFill : PocketSheetTheme.Color.fillMuted)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(
                        selected ? OnboardingTheme.selectionStroke : PocketSheetTheme.Color.hairline,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleFormat(_ format: OnboardingProductionFormat) {
        if let index = formats.firstIndex(of: format) {
            formats.remove(at: index)
        } else {
            formats.append(format)
        }
    }
}
