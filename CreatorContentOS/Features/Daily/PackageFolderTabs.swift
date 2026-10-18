import SwiftUI

/// Package body sections shown as horizontal file-folder tabs (Storyboard · Script · Caption).
enum PackageFolderTab: String, CaseIterable, Identifiable, Hashable {
    case storyboard
    case script
    case caption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storyboard: return "Storyboard"
        case .script: return "Script"
        case .caption: return "Caption"
        }
    }

    var accessibilityIdentifier: String {
        "plan.package.tab.\(rawValue)"
    }
}

/// Horizontal folder-style tabs: selected tab is ink on paper and joins the panel below.
struct PackageFolderTabs<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: PackageFolderTab
    @ViewBuilder var content: (PackageFolderTab) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip
            panel
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.package.folderTabs")
    }

    private var tabStrip: some View {
        tabLayout {
            ForEach(PackageFolderTab.allCases) { tab in
                folderTabButton(tab)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PocketSheetTheme.Color.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var tabLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 0))
    }

    private func folderTabButton(_ tab: PackageFolderTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Text(tab.title)
                .font(PocketSheetType.chip)
                .foregroundStyle(isSelected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.inkMuted)
                .padding(.horizontal, PocketSheetSpace.s)
                .padding(.vertical, PocketSheetSpace.xs)
                .frame(minHeight: 44)
                .background {
                    if isSelected {
                        UnevenRoundedRectangle(
                            topLeadingRadius: PocketSheetShape.controlRadius - 2,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: PocketSheetShape.controlRadius - 2,
                            style: .continuous
                        )
                        .fill(PocketSheetTheme.Color.paperRaised)
                    }
                }
                .overlay {
                    if isSelected {
                        UnevenRoundedRectangle(
                            topLeadingRadius: PocketSheetShape.controlRadius - 2,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: PocketSheetShape.controlRadius - 2,
                            style: .continuous
                        )
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                        .padding(.bottom, -1)
                    }
                }
                .zIndex(isSelected ? 1 : 0)
        }
        .buttonStyle(PocketSheetPressFeedbackStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    private var panel: some View {
        content(selection)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PocketSheetSpace.m)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: PocketSheetShape.sheetRadius,
                    bottomTrailingRadius: PocketSheetShape.sheetRadius,
                    topTrailingRadius: PocketSheetShape.sheetRadius,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: PocketSheetShape.sheetRadius,
                    bottomTrailingRadius: PocketSheetShape.sheetRadius,
                    topTrailingRadius: PocketSheetShape.sheetRadius,
                    style: .continuous
                )
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
            .accessibilityIdentifier("plan.package.panel.\(selection.rawValue)")
    }
}
