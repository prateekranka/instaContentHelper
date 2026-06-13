# Layers Surface: Creator Content OS V2 Full Intelligence MVP

Source inputs:

- V2 PRD draft: `/tmp/codex-remote-attachments/019e91d6-f797-7072-bc8c-b5db7482e6cf/D4864C26-EC4C-4E92-BC1D-B275F97C5DE7/1-creator-content-os-v2-prd.md`
- Conceptual model: `docs/layers-conceptual-model-creator-content-os-v2.md`
- Interaction flows: `docs/layers-interaction-flow-creator-content-os-v2.md`
- Previous reduced-MVP surface inventory: `docs/layers-surface-creator-content-os-v2-mvp.md`

This replaces the reduced first-TestFlight scope. The MVP now includes the full V2 intelligence system as a first-class product surface.

## Scope Change

Previous MVP goal:

- Prove the daily Creator loop first.
- Defer most intelligence surfaces.

New MVP goal:

- Build the complete daily content operating system in the first TestFlight version.
- Include daily use, weekly planning, source/reference intake, influencer watchlists, trend/pattern/audio intelligence, collabs/events, creator profile, archive, and learning.

This is no longer a narrow MVP. It is a **full internal V2 MVP**. The daily loop still must remain the product's center; the intelligence system exists to feed it, not replace it.

## Full MVP Navigation

### Creator Mode

Creator should still see a calm, minimal product:

- Today
- Week
- Archive
- Settings

Creator should not see the full intelligence machinery by default.

### Manager/Admin Mode

Manager needs the full operating surface:

- Today Preview
- Weekly Plan
- References
- Intelligence
- Collabs & Events
- Creator Profile
- Archive & Learnings
- Settings

Recommended admin navigation label decisions:

- `References` for raw source intake.
- `Intelligence` for Watchlists, Benchmark Creators, Patterns, Trends, Audio Options, and Ideas.
- `Collabs & Events` for Brand Briefs, Collab Leads, and Key Moments.
- `Archive` for completed Daily Cards and Post Results.
- `Learnings` can be a section inside Archive at first, not a separate nav item.

## Full MVP Screen Inventory

### 1. Today

Primary user: Creator.

Purpose:

- Show the current Published Daily Card and let Creator act.

Surface requirements remain unchanged from the reduced MVP:

- Title
- Why today
- Shootability
- Estimated shoot time
- Scenes, Script, Caption, Audio, Post
- Brand tab if relevant
- Need easier option
- Completion actions
- Feedback

Full-intelligence addition:

- Optional source explanation: `Inspired by a fitness-after-60 pattern` or `Uses a current audio reference`.
- Keep this small. It should not become an intelligence report.

### 2. Weekly Plan

Primary user: Manager. Secondary: Creator view-only.

Purpose:

- Review, edit, publish, and monitor a 7-day plan.

Must show:

- Seven Daily Cards
- Workout context
- Brand/Event flags
- Trend/Pattern/Audio flags
- Shootability
- Warnings
- Review state
- Completion state after publish

Admin actions:

- Generate week
- Open day
- Swap days
- Rebalance
- Inject Brand Brief
- Inject Key Moment
- Inject Trend/Pattern/Audio Option
- Publish

Surface requirement:

- Every day row must show why the card exists: `Routine`, `Brand`, `Moment`, `Trend`, `Pattern`, `Evergreen`, or combined source.

### 3. References

Primary user: Manager/scout.

Purpose:

- Add raw source material, analyze it, and confirm extraction.

Objects surfaced:

- Reference

Groups:

- Needs analysis
- Needs confirmation
- Confirmed
- Dismissed

Reference row/card must show:

- Source type: screenshot, reel link, audio link, note, import
- Preview or URL
- Added by
- Analysis status
- Extracted candidates count
- Provenance

Actions:

- Add screenshot/link
- Analyze
- Confirm extraction
- Dismiss
- Open source externally

Key language:

- `Reference` means raw source material.
- `Confirm extraction` means the system read it correctly.
- Do not use `Approve` here unless approving a derived Pattern/Trend/Audio Option/Idea.

### 4. Reference Review

Primary user: Manager.

Purpose:

- Inspect raw source and decide what it produced.

Must show:

- Raw source preview
- Extracted hook
- Extracted visual pattern
- Extracted caption pattern
- Extracted audio
- Suggested Pattern
- Suggested Trend
- Suggested Audio Option
- Suggested Idea
- Creator fit notes
- Avoid/copying warnings
- Confidence

Actions:

- Confirm extraction
- Approve as Pattern
- Approve as Trend
- Approve Audio Option
- Save as Idea
- Dismiss extraction item

Surface requirement:

- Derived objects must be visually separated. A Reference can produce multiple usable objects.

### 5. Intelligence Home

Primary user: Manager.

Purpose:

- Give a clean operating view of the source-intelligence system.

Sections:

- Watchlists
- Benchmark Creators
- Patterns
- Trends
- Audio Options
- Ideas

Hierarchy:

1. Items ready for this week
2. Items needing review
3. Recently used items
4. Archived/dismissed behind filters

Surface rule:

- Do not make this look like analytics. It is a preparation library.

### 6. Watchlists

Primary user: Manager.

Purpose:

- Manage curated source lists, including the top 500 female fitness influencers.

Watchlist row/card shows:

- Name
- Kind
- Source/provenance
- Creator count
- Last reviewed
- Status

Actions:

- Import list
- Review list
- Add creator
- Archive list

Empty state:

- `Import a creator list to learn formats, hooks, and patterns.`

Warning copy:

- `Use watchlists to learn formats, not copy scripts.`

### 7. Watchlist Import

Primary user: Manager.

Purpose:

- Import CSV/pasted creator lists.

Must show:

- Required fields
- Mapping preview
- Duplicate rows
- Invalid rows
- Missing provenance warning
- Import summary

Actions:

- Confirm import
- Fix mapping
- Cancel

Failure:

- `This list could not be imported. Some required fields are missing. Fix the mapping or save the raw list as a Reference.`

### 8. Benchmark Creator Detail

Primary user: Manager.

Purpose:

- Store why a creator matters and attach reference posts.

Must show:

- Handle/display name
- Platform
- Region
- Niche/audience tags
- Why relevant
- Priority score
- Creator relevance score
- Attached References
- Extracted Patterns/Trends if any

Actions:

- Add Reference
- Mark high priority
- Mark poor fit
- Archive

Surface warning:

- Do not show language that implies copying the creator.

### 9. Patterns

Primary user: Manager.

Purpose:

- Manage reusable non-time-sensitive content structures.

Pattern row/card shows:

- Title
- Pattern type
- Summary
- Creator adaptation
- Complexity
- Creator Fit Score
- Source References
- Used in cards count

Actions:

- Approve
- Reject
- Use this week
- Save as Idea
- Archive

Surface rule:

- Pattern pages should foreground `Creator adaptation`, not the external creator.

### 10. Trends

Primary user: Manager.

Purpose:

- Manage time-sensitive opportunities.

Trend row/card shows:

- Title
- Summary
- First seen
- Last seen
- Timing recommendation
- Region/niche
- Hook/visual/caption pattern
- Creator adaptation
- Saturation note
- Fit score
- Audio Options

Actions:

- Approve
- Reject
- Use today
- Use this week
- Save for later
- Mark stale

Surface rule:

- Trend freshness should be visible, but not more prominent than Creator fit.

### 11. Audio Options

Primary user: Manager. Secondary: Creator in Today audio section.

Purpose:

- Track audio choices and uncertainty.

Audio Option row/card shows:

- Audio name
- Source link
- Usage notes
- Region seen
- Availability confidence
- Verification status
- Fallback

Actions:

- Open in Instagram
- Mark available
- Mark unavailable
- Use this week
- Archive

Surface requirement:

- Availability must be explicit: `Candidate`, `Verified`, `Unavailable`, `Used`.

### 12. Ideas

Primary user: Manager.

Purpose:

- Keep unscheduled concepts that may become Daily Cards or backups.

Idea row/card shows:

- Title
- Summary
- Suggested use
- Shootability
- Fit score
- Source object if any

Actions:

- Schedule
- Use as backup
- Dismiss
- Archive

Surface decision:

- Ideas are not Daily Cards. They should not show full script/caption/posting package until scheduled/generated into a Daily Card.

### 13. Collabs & Events

Primary user: Manager.

Purpose:

- Manage Brand Briefs, Collab Leads, and Key Moments.

Sections:

- Brand Briefs
- Collab Leads
- Key Moments

Surface distinction:

- Brand Brief = obligation.
- Collab Lead = possible future brand.
- Key Moment = real-world context.

### 14. Brand Brief Detail

Must show:

- Brand
- Campaign
- Deliverable
- Due/post/review dates
- Required talking points
- Must avoid
- Required tags
- Disclosure
- Approval state
- Usage rights
- Payment/barter status if present
- Linked Daily Cards

Actions:

- Attach to week
- Mark scheduled
- Mark approval needed
- Mark approved
- Mark completed
- Archive

Warning:

- `This brief is missing disclosure or required tags. Cards using it cannot be published yet.`

### 15. Collab Lead Detail

Must show:

- Brand name
- Category
- Fit notes
- Contact/status notes
- References

Actions:

- Save
- Add note
- Promote to Brand Brief
- Dismiss

Surface rule:

- Collab Leads do not constrain Weekly Plan generation unless explicitly selected as inspiration.

### 16. Key Moment Detail

Must show:

- Name
- Date
- Location
- Kind
- Content angle
- Required scenes
- Pre/post-event notes
- Linked Daily Cards

Actions:

- Add to week
- Use as content angle
- Archive

### 17. Creator Profile

Primary user: Manager. Creator advanced access.

Purpose:

- Edit product memory.

Sections:

- Positioning
- Voice rules
- Content pillars
- Preferred hooks
- Caption style
- Things Creator would never say
- Weekly routine
- Brand tone
- No-go topics
- Language preferences
- Recurring formats
- Trend filter rules
- Influencer adaptation rules

Surface requirement:

- Profile edits should feel like editing a living brief, not code/config.
- Show active profile version.

### 18. Archive & Learnings

Primary user: Manager and Creator.

Purpose:

- See decisions and extract learning without becoming an analytics dashboard.

Archive entry shows:

- Date
- Daily Card title
- Completion state
- Caption/script used
- Feedback tags
- Trend/Pattern/Audio used
- Brand/Moment attached
- Optional final Instagram post link
- Optional manual performance notes

Learning Summary shows:

- Worked well
- Did not work
- Voice learnings
- Shootability learnings
- Brand learnings
- Trend learnings
- Next week recommendations

Actions:

- Generate Learning Summary
- Edit summary
- Use in next Weekly Setup

Surface rule:

- Keep learning qualitative first. Performance numbers are optional secondary detail.

## Full MVP Feedback And Error Decisions

### Intelligence Errors

Watchlist import failure:

- `This list could not be imported. Required fields are missing or mapped incorrectly. Fix the mapping, or save the file as a Reference.`

Reference analysis failure:

- `This Reference could not be analyzed. The screenshot may be unclear, the link may not be accessible, or the media may be unsupported. Save it as a note or try another source.`

Low fit warning:

- `This may not fit Creator. The style looks hard to shoot, off-voice, or too trend-led. Save for later or dismiss.`

Copying warning:

- `Use the structure, not the script. This Pattern should be adapted to Creator's real day.`

Audio uncertainty:

- `This audio has not been verified on Creator's account. Check in Instagram before posting or use the fallback.`

Brand blocking warning:

- `This Brand Brief is missing required disclosure or tags. Cards using it cannot be published until this is fixed.`

### Intelligence Success States

- Reference saved -> appears in `Needs analysis`.
- Reference analyzed -> appears in `Needs confirmation`.
- Extraction confirmed -> derived candidates become reviewable.
- Pattern approved -> appears in `Ready for planning`.
- Trend approved -> appears in `Ready for this week` if timely.
- Audio verified -> can be used without uncertainty warning.
- Learning Summary approved -> included in next Weekly Setup.

## Full MVP Hierarchy Rules

### Creator Surface

Most prominent:

- Today title
- What to shoot
- How hard it is
- What to copy
- Decision actions

Least prominent:

- Source intelligence
- Provenance
- Fit scores
- Admin warnings

### Manager Surface

Most prominent:

- What needs action
- What is ready for planning
- What blocks publishing
- What Creator will see

Secondary:

- Source details
- Fit scores
- Provenance
- Analysis confidence

Least prominent:

- Raw schema-like IDs
- Provider/API implementation details

## Full MVP Accessibility

Additional accessibility requirements beyond reduced MVP:

- Imported list review must be readable without horizontal spreadsheet-style scrolling as the only option.
- Source preview media must have textual extracted summaries.
- Fit score cannot rely on colour alone.
- Status chips need text labels: `Candidate`, `Approved`, `Stale`, `Verified`, `Unavailable`.
- Warning counts must expand into readable warning text.
- Long scripts/captions need comfortable text sizing and copy buttons close to content.
- Admin bulk screens should support search/filter, but first build can keep filtering simple.

## Full MVP Consistency Rules

Object treatments:

- Reference: source preview + extraction status + provenance.
- Pattern: reusable structure + Creator adaptation + source references.
- Trend: timing + adaptation + source count + freshness.
- Audio Option: audio name + verification status + fallback.
- Idea: unscheduled concept + suggested use.
- Daily Card: scheduled package + decision state.
- Brand Brief: obligation + constraints + approval/disclosure state.
- Key Moment: real-world date/context + content angle.
- Learning Summary: qualitative memory + next-week recommendations.

Action treatments:

- `Confirm` only for extraction accuracy.
- `Approve` only for fit/usefulness.
- `Publish` only for making the Weekly Plan visible to Creator.
- `Use this` only for alternatives.
- `Archive` for preserving history.
- `Dismiss` for not useful now.

## Updated Cross-Layer Issues

1. Full MVP requires a stronger implementation boundary than the surface layer can provide. The app should still be built in milestones even though all intelligence surfaces are in scope.
2. Watchlists and Benchmark Creators need a source-of-truth decision for the "top 500 female fitness influencers."
3. Pattern/Trend extraction quality may decide whether the full intelligence system feels useful or noisy.
4. Creator's surface must remain insulated from admin complexity.
5. Audio verification cannot be solved visually; the surface can only make uncertainty visible.

## Updated Build Milestones For Full MVP

Even with the full V2 intelligence system in the MVP, build order should still protect the daily loop:

1. App shell, pairing, role-based navigation.
2. Today, Daily Card, Package Detail, Decision Sheet, Archive.
3. Weekly Setup and Weekly Plan Review with sample/local data.
4. References: add, analyze placeholder, review, confirm.
5. Intelligence Home: Patterns, Trends, Audio Options, Ideas.
6. Watchlists and Benchmark Creators.
7. Collabs & Events.
8. Creator Profile editor.
9. Real Supabase sync and storage.
10. Real AI functions for Reference analysis and weekly generation.
11. Learning Summary.
12. End-to-end TestFlight proof.

## Surface Decisions To Make Before Coding

Priority 1:

- Role-based navigation structure.
- Full object list screens vs grouped Intelligence Home.
- Today card hierarchy.
- Weekly Plan day-row hierarchy.
- Reference Review extraction layout.

Priority 2:

- Fit score presentation.
- Status chip system.
- Warning system.
- Source provenance treatment.
- Audio verification treatment.

Priority 3:

- Editorial visual style.
- Icon direction.
- Photo/reference preview treatment.
- Motion/transition tone.

## Practical Warning

Including the full V2 intelligence system in the MVP is coherent, but it changes the risk profile:

- The first TestFlight build becomes an internal operating system, not a quick daily-card prototype.
- The daily loop can be delayed by admin/intelligence complexity.
- The UI will need strong information architecture from day one.
- AI quality and source review quality become core MVP risks, not later enhancements.

The design can support this, but implementation should still proceed in vertical slices. The first slice should prove that one Reference can become one approved Pattern/Trend/Audio Option, which can feed one Weekly Plan, which publishes one Daily Card Creator can use.

