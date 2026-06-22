# UI Experience QA Checklist

Use this checklist before sharing a TestFlight build.

## Creator Mode

- Today ready state shows the date, one tappable daily card, a clear effort chip, and a visible Shoot Folio affordance.
- Today missing state says nothing is scheduled without exposing backend terms.
- Creator profile opens from Today and the bottom Profile tab.
- Shoot Folio shows scene progress as `n of total scenes shot`.
- Each scene opens a detail page with capture guidance and a `Mark shot` action.
- `Mark all as shot` updates the completion state and shows a confirmation banner.
- Profile shows account details, creator profile, archive, manager access when allowed, then data source details.
- Archive filters work for All, Posted, Backups, and Skipped, and rows open detail.

## Manager Mode

- Weekly shows the workflow order: Brief, Generate, Review, Publish.
- Weekly Brief is at the top and editable from the header or any brief row.
- Readiness counts filter the day list and tap again to clear the filter.
- Generated drafts show day count, warning count, generated time, strategy, and `Review draft`.
- Day rows open detail and allow Ready, Backup, or Open state changes before publish.
- Idea Bank does not show exact duplicate ideas and selecting an idea shows confirmation.
- References starts with items needing review, then import, then library shelves.
- QA reads as live-data verification and shows current repository/generation/publish signals.

## Accessibility And Polish

- Small status text remains readable on the simulator at default and larger text sizes.
- Primary actions are reserved for generate, publish, mark shot, and open weekly from missing Today.
- Success, warning, live/info, and error states use distinct colors.
- Empty states avoid Supabase, edge-function, or database jargon in creator mode.
