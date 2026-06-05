# Visual Design Iterations: Mamta Content OS V2

Skills used:

- Iteration 1: `impeccable`
- Iteration 2: `high-end-visual-design`

Inputs:

- `docs/swiftui-design-system-and-implementation-spec-mamta-content-os-v2.md`
- `docs/swiftui-build-implementation-spec-mamta-content-os-v2.md`
- `docs/swiftui-liquid-glass-review-mamta-content-os-v2.md`
- Original Mamta Daily Mode concept board, now superseded: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21af17bf7881919860e24aa72a9200.png`
- Original Prateek Weekly Control concept board, now superseded: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21af9a792881918ddeece7f9c76aa5.png`
- Original Intelligence System concept board, now superseded: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21b02438f88191b438814a07d5f43c.png`
- Canonical Training Folio Mamta Daily Mode board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21baf5b41481919325834854242dec.png`
- Canonical Training Folio Prateek Weekly Control board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21bbdccef48191b828f54a07d944bd.png`
- Canonical Training Folio Intelligence System board: `/Users/prateekranka/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21be44255c81918f32f4e8dd2ab875.png`

Current status:

- The regenerated Training Folio boards are canonical. The original boards are retained only as the design problem this iteration corrected.

Note:

- `impeccable` project context files (`PRODUCT.md`, `DESIGN.md`) do not exist in this workspace. This pass uses the existing PRD/Layers/SwiftUI specs as product context.

## Iteration 1: Impeccable Product Critique

Register: product.

Physical scene:

Mamta opens the app on her iPhone in the morning, likely between real-life commitments, and needs one calm decision: can I shoot this today or should I preserve momentum another way?

Admin scene:

Prateek uses the same iPhone app to prepare and correct the week. He needs editorial control, but not a miniature database UI.

### Diagnosis

The current boards are visually strong, but too data heavy because they expose product-model attributes too early.

Symptoms:

- Rows show source type, provenance, status, counts, timing, warnings, fit, and actions at the same level.
- Admin screens feel like clean tables with better typography, not yet like an editorial operating surface.
- Intelligence Home is still count-driven. Counts are useful, but they make the screen read like analytics.
- Weekly Plan rows reveal too much per day. The week should be scannable as a rhythm first, not as seven mini reports.
- Reference Review is useful but over-explains. It should separate `What the system saw` from `What Prateek can use`.
- Liquid Glass is correctly sparse, but the content density still makes the interface feel busier than the material direction.

### New Product Design Rule

Every screen gets one of four density modes:

- `Glance`: one decision or one next action. Mamta Today, Archive summary, Publish Confirmation.
- `Plan`: a sequence with limited metadata. Weekly Plan, Weekly Setup, Collabs & Events.
- `Review`: compare source, extracted meaning, and approval. Reference Review, Daily Card Review.
- `Library`: browse prepared material. Intelligence Home, Patterns, Trends, Audio Options, Ideas.

The UI must not mix all four modes on one screen.

### Universal Density Limits

Mamta screens:

- One hero idea.
- Maximum two visible metadata chips.
- Maximum two primary visible actions.
- Source intelligence is one sentence.
- Everything else is behind Package Detail, Decision Sheet, or Archive Entry.

Admin list rows:

- One title.
- One short reason line.
- Maximum two chips.
- One trailing state or action.
- No inline provenance unless the row is specifically a Reference row.

Admin detail screens:

- One primary preview.
- One warning/action summary.
- One editable section open at a time.
- Secondary metadata appears in disclosure sections.

Intelligence screens:

- Show action queues, not object counts first.
- Counts can appear as small trailing details.
- Fit/adaptation language outranks provenance.

### Screen Improvements

#### Mamta Today

Current issue:

- The hero card is good, but the visible metadata stack still feels like a checklist before she has committed.

Improve:

- Keep title, date/context, one `Easy • 12 min` chip, and one `Why today` sentence.
- Move detailed shootability/time/source explanation into the package detail.
- Primary visible action: `See what to shoot`.
- Secondary visible action: `Not today`.
- Rename `Need easier option` to `Not today` on the home screen. It maps better to the actual decision flow and lowers guilt.

#### Package Detail

Current issue:

- Scenes, caption preview, audio, and readiness compete.

Improve:

- First open to `Scenes` only.
- Keep the active section large and calm.
- Collapse Caption, Audio, Post into tabs without previews on the first viewport.
- Copy actions sit near each content block, not in a global action strip.

#### Decision Sheet

Current issue:

- Mostly right.

Improve:

- Make `Not today` the branch, then show three backup options with one-line outcomes.
- Do not show explanatory reassurance text unless completion is selected.
- Keep backup option rows paper, not glass.

#### Mamta Archive

Current issue:

- The archive reads like a mini log with too many statuses.

Improve:

- Default to a weekly editorial timeline:
  - Date.
  - Title.
  - Decision state.
  - One output line.
- Hide thumbnails unless a post link/image exists.
- Move feedback tags and source objects to Archive Entry detail.

#### Weekly Setup

Current issue:

- Looks like setup checklist plus counts.

Improve:

- Treat it as a `Weekly Brief`.
- Sections:
  - Place.
  - Body.
  - Family/travel.
  - Obligations.
  - Source pulse.
  - Boundaries.
- Show completion as `Ready`, `Needs detail`, or `Missing`, not `4/6` as the main visual.
- Use counts only inside section rows.

#### Weekly Plan

Current issue:

- Seven rows are clean but still dense.

Improve:

- First viewport should show the week as rhythm:
  - Day/date.
  - Title.
  - Source reason chip.
  - Shootability dot or word.
  - Warning marker only if needed.
- Move workout context, audio confidence, and brand/event details into day detail.
- Add a top `Week Readiness` strip:
  - `5 ready`
  - `1 warning`
  - `1 brand check`
- This is summary, not analytics.

#### Daily Card Review

Current issue:

- Good hierarchy with Mamta Preview first, but too many editable package rows show immediately.

Improve:

- Keep `Mamta Preview` as the visual anchor.
- Show `Blocking issues` only if present.
- Show one open editable section at a time.
- Put source explanation below package sections.
- Put edit history in overflow/detail, not first view.

#### Publish Confirmation

Current issue:

- Useful but checklist heavy.

Improve:

- First viewport:
  - Notification preview.
  - `All 7 days ready` or blocking issue.
  - Primary `Publish week`.
- Move key notes and summary behind `Review details`.

#### References Inbox

Current issue:

- Too many reference attributes are visible in each row.

Improve:

- Convert to action queues:
  - `Needs analysis`
  - `Needs confirmation`
  - `Confirmed`
- Each row:
  - Preview.
  - One label: Screenshot, Reel link, Audio link, Note.
  - One line: `Added today by Prateek`.
  - One state: `Not analyzed`, `5 candidates`, `Confirmed`.
- Hide URL, provenance detail, exact timestamps, and candidate counts beyond one trailing label.

#### Reference Review

Current issue:

- It shows raw source, source details, extraction summary, fit notes, and actions all at once.

Improve:

- Three zones:
  1. `Source`: preview plus one provenance line.
  2. `What the system saw`: hook, visual pattern, caption pattern, audio.
  3. `What can become useful`: Pattern, Trend, Audio Option, Idea.
- Only zone 3 uses approval actions.
- Confidence and copying warning sit between zones 2 and 3.

#### Intelligence Home

Current issue:

- It reads like a library index with counts.

Improve:

- Make it an editorial shelf:
  - `Ready for this week`
  - `Needs your call`
  - `Recently used`
- Below that, show library sections as quieter navigation.
- Counts become trailing small text, not the focal point.
- Remove “feeds the week” instructional copy from the visible UI once the product is understood.

#### Pattern/Trend/Audio Detail

Current issue:

- Detail pages are field-heavy.

Improve:

- Lead with the Mamta adaptation.
- Then show:
  - Fit.
  - Timing/availability.
  - Avoid.
  - Source provenance.
- `Use this week` stays pinned in a sparse glass command bar.

## Iteration 2: High-End Visual Design Pass

Chosen visual archetype:

- Editorial Luxury, adapted for native iOS.

Rejected:

- Ethereal Glass. It would fight the warm fitness journal direction and make the app feel like a generic AI product.
- Heavy bento/card grids. They would increase the current density problem.

New visual concept:

`Training Folio`.

The app should feel like a private editorial folio for Mamta's week: paper, numbered days, calm photo crops, strong serif titles, disciplined red actions, sparse iOS 26 glass only around commands.

### Visual Principles

#### 1. Fewer Boxes, More Folio Structure

Replace many equal-weight cards with:

- Large hero surfaces.
- Thin rule-separated rows.
- Section ledgers.
- Folio-style day numbers.
- One primary editorial block per screen.

Use cards only for:

- Today hero.
- Mamta Preview.
- Media/source previews.
- Modal option choices.

Do not put cards inside cards.

#### 2. Typography Carries Hierarchy

Use:

- Large serif titles for screen and card identity.
- SF-style body for UI and copyable text.
- Tiny uppercase section labels only as quiet editorial markers.
- Large day numerals in Weekly Plan and Archive.

Avoid:

- Many similarly sized labels.
- Display type inside compact rows.
- All-caps metadata everywhere.

#### 3. One Accent At A Time

Oxblood should mark:

- Primary action.
- Selected tab/filter.
- Important admin action.
- Blocking state when needed.

It should not appear on every status, icon, count, and heading at once.

Use sage/brass for softer readiness signals.

#### 4. Photography As Context, Not Decoration

Use optional imagery in three places:

- Today hero texture/context.
- Mamta Preview thumbnail.
- Reference/source preview.

Do not add decorative stock-like images elsewhere.

#### 5. Liquid Glass As Chrome, Not Content

Use Liquid Glass for:

- Native nav/tab/sheet material.
- Floating icon controls.
- Pinned bottom command bars.

Do not use Liquid Glass for:

- JournalBlock.
- Long text.
- List rows.
- Warnings.
- Dense library shelves.

### Revised Screen Direction

#### Mamta Today: `One Best Idea`

First viewport:

- Monogram, `Today`, date/context.
- One large editorial hero:
  - title.
  - `Easy • 12 min`.
  - one why-today sentence.
- Bottom glass command bar:
  - oxblood `See what to shoot`.
  - paper/glass secondary `Not today`.

No visible package preview on home.

#### Package Detail: `Shoot Folio`

First viewport:

- Section tabs remain, but only active section content appears.
- Scenes are large, numbered, and airy.
- Each scene row has:
  - large numeral.
  - short cue.
  - duration pill.
  - optional thumbnail.

Caption/script/audio are separate focused sections.

#### Weekly Plan: `Seven-Day Rhythm`

First viewport:

- Large title: `Weekly Plan`.
- Readiness strip.
- Seven-day rhythm list:
  - oversized day abbreviation or date numeral.
  - title.
  - source reason.
  - one status.

Open day for details. Do not show every attribute in the row.

#### Weekly Setup: `Weekly Brief`

Use editorial sections instead of checklist density.

Each section:

- Icon.
- Title.
- One summary sentence.
- State chip.

Examples:

- `Place`: Mumbai, race week, early mornings.
- `Body`: 3 runs, 1 gym, 1 race.
- `Obligations`: Puma needs disclosure.
- `Source pulse`: 6 approved trends/audio.
- `Boundaries`: politics, weight talk, negativity.

#### Daily Card Review: `Mamta Preview First`

First viewport:

- Mamta Preview card.
- Blocking issue strip only if needed.
- One open package section.
- Bottom glass command bar.

Everything else is disclosure.

#### References: `Editorial Inbox`

First viewport:

- Three quiet queue headers.
- Only the highest-priority item expanded per queue.
- Add/filter controls are glass.
- Rows stay paper.

#### Reference Review: `Source To Usefulness`

Visual sequence:

- Large source preview.
- Extraction lens.
- Fit/copying warning.
- Derived candidates.
- Bottom command bar.

Make it feel like editorial review, not OCR output.

#### Intelligence: `Preparation Library`

First viewport:

- `Ready for this week` shelf with 2 to 3 items.
- `Needs your call` shelf with 1 to 2 items.
- Library navigation below.

Avoid count-first rows like `Patterns 24`, `Trends 19` as the main visual. Counts can be quiet trailing text.

#### Archive: `Decision Journal`

First viewport:

- Weekly timeline.
- Large date markers.
- One line per day.
- Decision state in human language:
  - `Posted`.
  - `Used backup`.
  - `Saved for tomorrow`.
  - `Skipped after decision`.

Archive details live one tap deeper.

## Updated Component Direction

### Add `DensityMode`

```swift
enum DensityMode {
  case glance
  case plan
  case review
  case library
}
```

Use this in documentation and previews. It does not need to be a runtime dependency unless useful.

### Add `FolioRow`

A quiet row primitive for Weekly Plan, Archive, and Intelligence shelves.

Visual contract:

- Large leading date/number/icon slot.
- Title.
- One secondary line.
- Maximum two chips.
- Optional trailing action/state.

### Add `ReadinessStrip`

Use only for admin summary screens.

Visual contract:

- Three compact labels maximum.
- No charts.
- No large KPI numerals.

### Add `EditorialDisclosure`

Use to hide secondary metadata.

Use for:

- Source provenance.
- Confidence.
- Edit history.
- Full brand requirements.
- Related references.
- Learning details.

### Revise `StatusChip`

Status chips should be quieter:

- Smaller.
- Lower contrast.
- Text-first.
- No more than two visible per row.

### Revise `WarningRow`

Warnings should not appear everywhere. Use:

- One warning strip for summaries.
- Full warning list only inside details or blocking states.

## Imagegen Direction For Revised Boards

If regenerating boards, use these constraints:

- Show less visible data per screen.
- More whitespace.
- Larger typography.
- Fewer boxes.
- One editorial hero or shelf per screen.
- Admin rows should show title, reason, and one or two chips only.
- Liquid Glass only on nav, floating controls, and bottom command bars.
- No translucent content cards.

## Acceptance Tests

The revised design passes when:

- Mamta Today can be understood in under 5 seconds.
- Mamta sees one content idea, not a planner.
- Weekly Plan can be scanned without reading metadata.
- Reference Review clearly separates source, extraction, and approval.
- Intelligence Home no longer reads as analytics.
- No dense list shows more than two chips per row.
- No primary screen has more than one dominant block.
- Liquid Glass is visible but not the aesthetic headline.
