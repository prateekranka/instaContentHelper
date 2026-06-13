# Layers Orient: Creator Content OS V2 PRD

Source reviewed: `/tmp/codex-remote-attachments/019e91d6-f797-7072-bc8c-b5db7482e6cf/D4864C26-EC4C-4E92-BC1D-B275F97C5DE7/1-creator-content-os-v2-prd.md`

## Decision Landscape

| Layer | State | Notes |
|---|---|---|
| Observed behaviour | Partial | The PRD is grounded in real repeated behaviour from Manager and Creator's current ChatGPT/custom GPT workflow: daily content packages, trend screenshots, HYROX/routine context, captions, audio, collabs, and weekly planning. It is still not backed by direct observation of Creator using a standalone app for a week. The MVP acceptance test correctly proposes that proof loop. |
| The domain | Partial | The PRD understands key real-world domain constraints: Instagram/Meta limitations, no unauthorized scraping, audio availability uncertainty, brand disclosure, influencer benchmarking as inspiration, and manual-first trend intake. Domain risk remains around the "top 500 female fitness influencers" source, licensed/approved provider options, audio availability verification, and what official APIs can actually provide. |
| User needs | Strong | The core need is sharp: Creator needs one prepared, shootable daily content package without researching, prompting, or managing a content calendar. Manager needs weekly setup/admin control. The PRD repeatedly protects shootability, voice fit, and low-friction daily use. |
| Product & service strategy | Strong, with scope pressure | The strategy is explicit: bespoke Creator-first iPhone app, daily card as the product, manual/source-list-first intelligence engine, SwiftUI/Supabase, no public SaaS onboarding, no in-app editing, no direct publishing required. The main strategic risk is V2 scope expansion: influencer watchlists, reference post analysis, trend clustering, collabs/events, source imports, learning summaries, and performance snapshots may exceed the first proof loop unless phased tightly. |
| Conceptual model | Partial | The PRD lists many objects and schema tables, but the actual product model is not yet resolved as a user-facing ontology. Objects such as `trend_observation`, `trend_cluster`, `content_pattern`, `reference_post`, `idea_bank_item`, `audio_candidate`, `brand_item`, `key_moment`, and `daily_card_reference` need clearer relationships, ownership, lifecycle states, and vocabulary. This is the lowest load-bearing layer with unresolved design risk. |
| Interaction structure and flow | Partial | Core flows are described: weekly setup, daily Creator flow, midweek changes, trend/influencer refresh, review/edit/publish, and pairing. The flows are not yet breadboarded. Critical decision points need mapping: how an imported source becomes a pattern, how a pattern becomes a card, how card alternatives are previewed/accepted, how midweek changes affect soft-locked days, and what the user sees during analysis/generation failures. |
| Surface | Partial / not started | A visual direction exists: premium editorial fitness journal, not SaaS dashboard. Screen lists and card sections are detailed. But no surface system, hierarchy, sample UI, empty/loading/error states, or visual treatment of source intelligence has been decided. Surface should wait until the conceptual model and flow are stable. |

## Bottleneck Layer

**Bottleneck: Conceptual model.**

The V2 PRD has moved from a simple weekly-prepared daily content app into a content intelligence system. The lowest risky unresolved layer is now the model of what exists in the product:

- Is a manually pasted reel a `reference_post`, a `trend_observation`, both, or an input that later becomes one of those?
- Is a `content_pattern` derived from one reference, many references, or manually authored by Manager?
- What is the difference between an `idea_bank_item`, a `daily_card`, a `backup`, and an approved `content_pattern`?
- Does an `audio_candidate` exist independently from a trend cluster, or only as part of one?
- Are `brand_items` and `key_moments` both schedule constraints, or different object classes with different behavior?
- What does "approved" mean across trends, patterns, references, source lists, and weekly plans?
- Which objects are visible to Creator, which are admin-only, and which are just backend provenance?
- What gets archived, what gets learned from, and what stays as source material?

Without resolving this model, the app risks becoming a schema-driven admin tool rather than a clear product. It will also make the SwiftUI screens hard to design because many object types have overlapping meanings.

## Assumed Layers To Watch

### Observed behaviour

The PRD assumes Creator will actually use a daily card and give lightweight feedback. That is plausible, but unproven. The one-week MVP test should be treated as research, not just QA.

### Domain

The PRD correctly avoids scraping, but the influencer intelligence system still depends on source lists, screenshots, links, and possibly providers. The canonical source of the "top 500 female fitness influencers" list is still open, which affects the credibility and maintenance cost of the intelligence layer.

### Product strategy

The daily product strategy is strong, but the V2 MVP may be too wide. The strategy should explicitly separate:

- Daily proof loop required for value.
- Intelligence/admin system required to improve quality.
- Provider/API integrations deferred until after proof.

## Recommendation

Run `layers-conceptual-model` next.

The goal should be to create a user-facing conceptual model before any UI or schema hardening:

- Object inventory.
- Object definitions in plain product language.
- Relationships between objects.
- Lifecycle states and transitions.
- Visibility rules for Creator vs Manager.
- Vocabulary decisions.
- Which backend tables are implementation details rather than product concepts.

After that, run `layers-interaction-flow` to breadboard:

- Weekly setup to published week.
- Trend/reference intake to approved source.
- Today card decision flow.
- Midweek change injection.
- Card alternative preview and acceptance.
- Offline and failed-generation paths.

