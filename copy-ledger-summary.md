# Copy ledger summary

**Total rows:** 692

## Disposition counts

- **keep:** 557
- **rewrite:** 15
- **rewrite (proposed):** 1
- **cut:** 18
- **DEBUG:** 101

## Blockers

- Bobby launch decision unresolved: actual shared post within 60s vs time-to-first-useful-package (blocks C12 implementation, not ledger).
- C12 skip toast marked rewrite (proposed) until skippable-setup onboarding behavior lands.
- C1 Approve→Make ready requires error-map alignment (Tap Approve again, Approve could not…).
- Copy-only pass cannot restore Today main-package copy controls (separate implementation ledger).
- AdminShell strings retained as DEBUG; not shipped in Release consumer path.

## High-impact rewrite rows (seed candidates)

| ID | file:line | existing | proposed | evidence |
| --- | --- | --- | --- | --- |
| COPY-0231 | `CreatorContentOS/Features/Daily/PlanHubView.swift:487` | Approving… | Making ready… | C1: action verb; lifecycle unchanged |
| COPY-0233 | `CreatorContentOS/Features/Daily/PlanHubView.swift:496` | Clicking this will add the card to the Today page. | Remove or use date-aware readiness wording | C2: desktop Clicking; future dates must not promise immediate Today |
| COPY-0443 | `CreatorContentOS/Features/Today/NotTodaySheet.swift:69` | Keep the streak alive. |  | C3: decorative backup subtitles |
| COPY-0203 | `CreatorContentOS/Features/Daily/PlanHubView.swift:66` | Generation error | (drop title; show human message only) | C4: error tile title duplicates message noun |
| COPY-0225 | `CreatorContentOS/Features/Daily/PlanHubView.swift:403` | Deep reasoning takes a couple of minutes. Validation may retry once or twice. | Preparing your idea… | C5: remove internal reasoning/validation jargon |
| COPY-0487 | `CreatorContentOS/Features/Today/ShootFolioView.swift:543` | The creator can shoot this at home, in the society garden, or in the gym | You can shoot this at home or wherever makes the scene easiest to capture clearly and safely. | C6: third-person + India/HYROX default in client fallback |
| COPY-0490 | `CreatorContentOS/Features/Today/TodayView.swift:39` | Mark posted | Mark as posted | C7: unify with Shoot Folio |
| COPY-0489 | `CreatorContentOS/Features/Today/ShootFolioView.swift:296` | Today's published card does not include shoot scenes. | Today's ready card does not include shoot scenes. | C8: Ready package vocabulary; avoid machine voice |
| COPY-0198 | `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift:11` | Generation inputs | Idea settings | C9: avoid backend term generation |
| COPY-0273 | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:99` | Instagram couldn't be reached, so these references were not verified live. You can still add them —  | Instagram couldn't be reached, so these references were not verified live. You can still add them —  | C10: server is architecture jargon |
| COPY-0158 | `CreatorContentOS/Features/Archive/ArchiveView.swift:61` | Completed | Shot & posted | C11: Completed contradicts Skipped sibling filter |
| COPY-0431 | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:437` | Set up later — we'll ask again next launch | You can finish setup in You. | C12: proposed until skippable-setup behavior lands |
| COPY-0196 | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:124` | e.g. A quiet pre-race check-in before the first mile… | e.g. A low-key check-in about what I'm working on this week… | C13: HYROX-flavored placeholder example |
| COPY-0172 | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:360` | Resize scene column | Resize scene column | C14: keep working VoiceOver resize control |
