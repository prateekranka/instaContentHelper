import SwiftUI

// MARK: - Starting point (distinct from interest chips)

struct OnboardingStartingPointChip: View {
    let point: OnboardingStartingPoint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSheetSpace.xxs) {
                Image(systemName: point.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(point.displayLabel)
                    .font(PocketSheetType.chip)
            }
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .padding(.horizontal, PocketSheetSpace.m)
            .frame(minHeight: 44)
            .background(
                isSelected ? OnboardingTheme.startingPointFill : PocketSheetTheme.Color.paperRaised,
                in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(
                        isSelected ? OnboardingTheme.startingPointStroke : PocketSheetTheme.Color.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(point.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension OnboardingStartingPoint {
    var symbolName: String {
        switch self {
        case .justStarting: "sparkles"
        case .alreadyPosting: "arrow.up.right"
        }
    }
}

// MARK: - Interest chip (pastel fill + checkmark indicator)

struct OnboardingInterestChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSheetSpace.xxs) {
                Text(label)
                    .font(PocketSheetType.chip)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, PocketSheetSpace.s)
            .background(isSelected ? OnboardingTheme.selectionFill : PocketSheetTheme.Color.fillMuted)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(
                    isSelected ? OnboardingTheme.selectionStroke : PocketSheetTheme.Color.hairline,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Custom subject tag

struct OnboardingCustomSubjectTag: View {
    let subject: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: PocketSheetSpace.xxs) {
            Text(subject)
                .font(PocketSheetType.chip)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .accessibilityLabel("Remove \(subject)")
        }
        .foregroundStyle(PocketSheetTheme.Color.ink)
        .padding(.horizontal, PocketSheetSpace.s)
        .frame(minHeight: 44)
        .background(OnboardingTheme.selectionFill)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(OnboardingTheme.selectionStroke, lineWidth: 1)
        }
    }
}
