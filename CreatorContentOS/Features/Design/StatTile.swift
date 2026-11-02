import SwiftUI

/// A compact metric tile: label over a prominent value, with an optional delta line.
/// Shares the raised-paper treatment of the Today Format/Effort tiles, promoted for
/// reuse by the "How you're doing" insights surface.
struct StatTile: View {
    let label: String
    let value: String
    var delta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(label)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(value)
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let delta {
                Text(delta)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PocketSheetSpace.s)
        .background(
            PocketSheetTheme.Color.paperRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(delta.map { "\(label), \(value), \($0)" } ?? "\(label), \(value)")
    }
}
