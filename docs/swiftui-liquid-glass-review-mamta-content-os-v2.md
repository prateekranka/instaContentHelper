# SwiftUI Liquid Glass Review: Mamta Content OS V2

Generated with `build-ios-apps:swiftui-liquid-glass`.

Inputs:

- `docs/swiftui-design-system-and-implementation-spec-mamta-content-os-v2.md`
- `docs/swiftui-build-implementation-spec-mamta-content-os-v2.md`
- Canonical Training Folio Mamta Daily Mode board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21baf5b41481919325834854242dec.png`
- Canonical Training Folio Prateek Weekly Control board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21bbdccef48191b828f54a07d944bd.png`
- Canonical Training Folio Intelligence System board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21be44255c81918f32f4e8dd2ab875.png`

Superseded boards:

- The earlier, denser Mamta/Weekly/Intelligence boards are superseded and should not drive Liquid Glass placement or content density decisions.

Apple references checked:

- Liquid Glass overview: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- `glassEffect(_:in:)`: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- `GlassEffectContainer`: https://developer.apple.com/documentation/swiftui/glasseffectcontainer

## Verdict

Use Liquid Glass as a restrained iOS 26 system layer, not as the product's main visual material.

The product direction should remain:

- Warm ivory paper.
- Editorial serif typography.
- Thin rules and quiet structure.
- Oxblood actions.
- Muted sage/brass status language.

Liquid Glass should make navigation and commands feel native to iOS 26. It should not make Mamta's Daily Card, scripts, captions, Reference summaries, or Archive history translucent.

## Where Liquid Glass Should Be Used

### 1. System Navigation And Tab Bars

Use standard SwiftUI `TabView`, `NavigationStack`, toolbars, sheets, and menus first. On iOS 26, these standard components adopt the system Liquid Glass appearance automatically.

Targets:

- Mamta Mode bottom tabs: Today, Week, Archive, Settings.
- Admin Mode bottom tabs: Today Preview, Weekly Plan, References, Intelligence, More.
- Navigation bars on detail screens.
- Toolbar icons: settings, overflow, bookmark, filter, close.

Implementation direction:

- Do not build a custom tab bar for V1.
- Let native iOS 26 tab/navigation material carry the system feel.
- Keep custom styling focused on app content below the nav bars.

### 2. Bottom Action Bars

Use Liquid Glass for pinned command areas that float over scroll content.

Targets:

- Today bottom action area when the main card scrolls: `See what to shoot`, `Need easier option`.
- Package Detail bottom action: `I'm ready to shoot`.
- Decision Sheet bottom action: `Use backup`.
- Weekly Plan Review bottom action group: `Rebalance`, `Publish`.
- Daily Card Review bottom action group: `Create alternative`, `Approve card`.
- Publish Confirmation bottom action: `Publish week`.
- Reference Review bottom action group: `Confirm extraction`, approvals.
- Pattern/Trend/Audio detail bottom action: `Use this week`.

Implementation direction:

- Wrap grouped bottom actions in `GlassEffectContainer`.
- Use a single glass-backed bottom command container rather than making every content row glass.
- Keep the oxblood fill for truly decisive actions; use glass around the action area, not necessarily instead of the app's action color.

### 3. Compact Floating Controls

Use Liquid Glass for small controls that sit above content.

Targets:

- Settings/control icon in Mamta Today.
- Admin filter button in References.
- Admin overflow menu.
- Package Detail bookmark/save icon.
- Archive filter/sort controls.
- Reference source preview overlay controls such as open/copy only if over media.

Implementation direction:

- Use `.glassEffect(.regular.interactive(), in: .circle)` for icon-only controls.
- Keep the control size stable: 36 to 44 points.
- Use `GlassEffectContainer` when multiple floating controls appear together.

### 4. Sheets And Confirmation Surfaces

Use native iOS 26 sheet presentation and restrained glass for command areas inside sheets.

Targets:

- Decision Sheet.
- Alternative Request.
- Alternative Preview.
- Add Reference.
- Extraction Results.
- Generation Check.
- Midweek Change Type.
- Impact Preview.

Implementation direction:

- Sheet content stays paper-like.
- Sheet grabber/navigation/toolbars can use native system appearance.
- Bottom command row can use a glass container.
- Avoid a glass background behind long text or structured checklists.

### 5. Segmented Controls And Mode Switchers

Use glass selectively for compact, high-level selection controls.

Targets:

- Today decision intent: `Yes, I can` / `Not today`.
- Package tabs only if the native segmented treatment reads cleanly.
- Archive filters: All, Posted, Backup used, Saved, Skipped.
- Intelligence filters: Ready, Needs review, Recently used.

Implementation direction:

- Prefer native segmented controls first.
- If custom tabs are needed for the editorial look, use a paper control with an oxblood selected underline rather than glass.
- Use glass only when the control floats or sits in a toolbar/action region.

## Where Liquid Glass Should Not Be Used

### 1. Daily Card Content

Do not apply Liquid Glass to:

- Today hero card.
- Daily Card title area.
- Why today.
- Shootability/time rows.
- Source explanation.
- Backup option rows.

Reason:

- Mamta needs calm certainty. Glass here makes the core content feel less grounded and harder to read.

Use instead:

- `paperRaised` fill.
- Thin hairline stroke.
- Editorial typography.
- Optional warm image crop with dark overlay only inside hero context.

### 2. Long Reading Surfaces

Do not apply glass to:

- Script text.
- Caption text.
- Scene list rows.
- Brand brief requirements.
- Creator Profile sections.
- Learning Summary paragraphs.

Reason:

- Blurred/translucent surfaces reduce text comfort. These are reading and copying surfaces, not chrome.

### 3. Dense Admin Lists

Do not apply glass to every row in:

- Weekly Plan seven-day list.
- References Inbox.
- Intelligence Home.
- Archive entries.
- Collabs & Events lists.

Reason:

- Many simultaneous glass effects can become visually noisy and can hurt rendering performance.

Use instead:

- Paper rows.
- Thin separators.
- Small status chips.
- Glass only for sticky filters or bottom command groups.

### 4. Status Chips By Default

Do not make every `StatusChip` glass.

Reason:

- Chips communicate state quickly. Tint and text should be primary. Glass adds ambiguity and can dilute warnings.

Use glass only for:

- Selected filter chips in a floating filter bar.
- Tappable chip groups that behave like controls.

### 5. Warning And Blocking States

Do not use glass for blocking warnings.

Targets:

- Brand Brief missing disclosure/tags.
- Audio unverified.
- Low Mamta fit.
- Copying warning.
- Publish blocked.

Reason:

- Warnings need stable contrast and explicit hierarchy.

Use instead:

- Paper/clay warning block.
- Icon + readable message.
- Oxblood for blocked state.

## iOS 26 SwiftUI Component Guidance

### `MCOGlass`

Add a small design-system namespace so glass decisions stay centralized.

Suggested file:

- `DesignSystem/MCOGlass.swift`

Suggested API:

```swift
enum MCOGlass {
  static let floatingControlRadius: CGFloat = 22
  static let commandBarRadius: CGFloat = 18
  static let chipRadius: CGFloat = 999

  static var commandTint: Color {
    MCOTheme.Color.paperRaised.opacity(0.72)
  }

  static var oxbloodTint: Color {
    MCOTheme.Color.oxblood.opacity(0.22)
  }
}
```

### `GlassCommandBar`

Use for pinned bottom actions.

Suggested file:

- `DesignSystem/Components/GlassCommandBar.swift`

Contract:

```swift
struct GlassCommandBar<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    GlassEffectContainer(spacing: MCOSpace.s) {
      HStack(spacing: MCOSpace.s) {
        content
      }
      .padding(.horizontal, MCOSpace.m)
      .padding(.vertical, MCOSpace.s)
      .glassEffect(
        .regular.tint(MCOGlass.commandTint),
        in: .rect(cornerRadius: MCOGlass.commandBarRadius)
      )
    }
  }
}
```

Notes:

- Apply `.glassEffect(...)` after layout and visual modifiers.
- If buttons inside are distinct glass buttons, wrap them in the same `GlassEffectContainer`.
- Do not place long text blocks inside `GlassCommandBar`.

### `FloatingIconButton`

Use for top-right controls and media overlays.

Suggested file:

- `DesignSystem/Components/FloatingIconButton.swift`

Contract:

```swift
struct FloatingIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .medium))
        .frame(width: 40, height: 40)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .accessibilityLabel(accessibilityLabel)
  }
}
```

### `PrimaryActionButton`

Keep the app's oxblood identity. Do not replace every primary button with `.glassProminent`.

Use:

- Oxblood filled button for content-critical decisions.
- `.buttonStyle(.glassProminent)` only when the button lives in a glass command context and still retains oxblood tint or label contrast.

Recommended rule:

- Mamta primary actions: oxblood fill inside or adjacent to glass command bar.
- Admin primary publish/approve actions: oxblood fill.
- Secondary controls in command bars: `.buttonStyle(.glass)`.

### `SecondaryActionButton`

Use paper/hairline by default.

Use `.buttonStyle(.glass)` only when:

- The button is in a floating bottom action group.
- The background behind the action group scrolls.
- The action is clearly tappable and compact.

### `StatusChip`

Default:

- Paper fill.
- Hairline stroke.
- Text label and optional SF Symbol.

Glass variant:

- Add `isInteractive: Bool`.
- Only interactive selected filter chips can use `.glassEffect(.regular.interactive(), in: .capsule)`.

Do not use glass for non-interactive warning chips.

### `EditorialTabs`

Default:

- Paper tabs with oxblood selected underline, as shown in the concept boards.

Glass variant:

- Only use for floating or toolbar-level tabs, not package content tabs.

### `JournalBlock`

No glass.

Use:

- `paperRaised`
- 1 point hairline stroke
- radius 8

Reason:

- This is the app's content material. It should feel like journal paper, not chrome.

### Sheets

Use:

- Native sheet presentation.
- Paper content.
- Glass bottom command bar when pinned actions are present.

Do not:

- Apply a glass material to the full sheet content background.
- Put a glass effect under dense option lists.

### Toolbars

Use:

- Native SwiftUI toolbar APIs.
- Standard SF Symbol toolbar items.
- Group related actions.

Do not:

- Build custom top chrome unless a screen needs a bespoke editorial header.

### Transition And Motion

Use Liquid Glass morphing only where a command cluster changes shape.

Good candidates:

- Decision Sheet `Yes, I can` -> `Not today` backup controls.
- Floating filter chips expanding into filters.
- Alternative Preview command row swapping `Use this` / `Keep original`.

Avoid:

- Morphing content rows.
- Morphing Daily Card surfaces.
- Decorative glass animations.

## Required Spec Changes Before Implementation

### 1. Add `MCOGlass.swift`

The current specs mention Liquid Glass but do not define a central API. Add `DesignSystem/MCOGlass.swift` to the file structure before coding.

### 2. Add `GlassCommandBar.swift`

The first build should not hand-roll bottom action bars per screen. Add one reusable `GlassCommandBar` component and use it in:

- Today.
- Package Detail.
- Decision Sheet.
- Weekly Plan Review.
- Daily Card Review.
- Reference Review.
- Intelligence detail screens.

### 3. Clarify That `JournalBlock` Is Never Glass

The existing design-system spec says core reading surfaces stay paper-like. Make this stricter in implementation:

- `JournalBlock` must not call `.glassEffect`.
- If a screen needs glass, wrap command chrome outside the content block.

### 4. Split Button Styling By Context

The existing specs list `PrimaryActionButton` and `SecondaryActionButton`, but iOS 26 needs context-specific behavior:

- `PrimaryActionButton`: oxblood identity by default.
- `PrimaryActionButton` inside `GlassCommandBar`: oxblood content with glass container, not necessarily `.glassProminent`.
- `SecondaryActionButton` inside `GlassCommandBar`: can use `.buttonStyle(.glass)`.

### 5. Add Liquid Glass Quality Gates

Add these gates before the first simulator visual pass:

- No dense list has more than one glass region unless the extra region is system navigation.
- No long reading surface uses glass.
- All custom glass groups with multiple glass children use `GlassEffectContainer`.
- `.glassEffect(...)` is applied after frame/padding/background modifiers.
- `.interactive()` is only used on tappable/focusable elements.
- Oxblood primary actions still pass contrast against their background.

### 6. Confirm Visual Direction In Simulator

The generated boards are deliberately less glassy than iOS 26 defaults. When the first app runs:

- Verify standard tabs/toolbars do not overpower the warm editorial paper.
- If default system chrome feels too cool or glossy, reduce custom glass usage elsewhere rather than fighting system chrome.
- Preserve the Daily Card as the visual anchor.

## Screen-Level Recommendations

### Mamta Today

Use glass:

- System tab bar.
- Settings icon.
- Bottom command bar if actions are pinned over scroll content.

Do not use glass:

- Hero card.
- Why today/shootability rows.
- Source note.

### Package Detail

Use glass:

- Bookmark toolbar icon.
- Bottom `I'm ready to shoot` command area.

Do not use glass:

- Package tabs.
- Scene rows.
- Caption/script text blocks.

### Decision Sheet

Use glass:

- Native sheet chrome.
- Bottom `Use backup` command area.
- Possibly the two-option intent toggle if it floats.

Do not use glass:

- Backup option rows.

### Weekly Plan Review

Use glass:

- Native tab/navigation chrome.
- Bottom `Rebalance` / `Publish` command bar.
- Optional filter/sort controls.

Do not use glass:

- Seven day rows.
- Warning rows.

### Daily Card Review

Use glass:

- Top toolbar controls.
- Bottom `Create alternative` / `Approve card` command bar.

Do not use glass:

- Mamta Preview card.
- Package rows.
- Warnings.

### References

Use glass:

- Add/filter controls.
- Bottom quick action bar if pinned.

Do not use glass:

- Reference rows.
- Raw source summary rows.

### Reference Review

Use glass:

- Source preview overlay controls.
- Bottom confirmation/approval command bar.

Do not use glass:

- Extraction summary.
- Derived candidate blocks.
- Mamta fit notes.

### Intelligence

Use glass:

- Section filter chips only if interactive and floating.
- Bottom `Use this week` action.

Do not use glass:

- Intelligence Home section rows.
- Pattern/Trend/Audio detail reading blocks.

### Archive

Use glass:

- System tabs/navigation.
- Optional filter strip only if interactive.

Do not use glass:

- Archive entries.
- Learning summaries.

## Implementation Order Update

Before Slice 1:

1. Add `MCOGlass`.
2. Add `GlassCommandBar`.
3. Update `PrimaryActionButton` and `SecondaryActionButton` to support command-bar context.
4. Add previews for:
   - `GlassCommandBar`
   - `FloatingIconButton`
   - `TodayView` with pinned glass command bar
   - `DecisionSheet` with paper backup rows and glass bottom command

Then continue with the existing Slice 1 and Slice 2 plan.
