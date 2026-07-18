# Product

## Register

product

## Users

Creator is the primary daily user. She opens the iPhone app from a morning routine, sees the prepared content card for today, decides whether she can shoot it, copies the package she needs, requests an easier option when needed, and marks the day state. She should not have to prompt, research, or manage a content calendar.

Manager is the admin/operator. Manager maintains the creator profile, prepares weekly context, imports references, generates one daily card at a time from an explicit daily brief and target date, reviews and edits daily cards, publishes when ready, and monitors whether Creator has usable content.

Future users may include editors, helpers, coaches, scouts, and additional creators inside workspaces, but the V1 surface remains bespoke and role-focused.

## Product Purpose

Content Helper turns a weekly setup pass by Manager into a clear daily content workflow for Creator. It replaces scattered planning across ChatGPT, screenshots, links, notes, and manual coordination with one shared native iPhone app backed by Supabase.

Success means Manager can generate and publish high-quality daily Instagram content cards, and Creator can open the app each day and know exactly what to shoot, say, caption, post, or use as a backup without entering strategy mode.

## Generation

Supported generation is **day-wise only**. Users generate one daily card at a time from an explicit daily brief and target date (today, tomorrow, or another chosen date).

Weekly batch generation, seven-day fan-out, and parallel day lanes are **removed** — not paused or hidden behind a flag. There is no supported path to generate a full week in one request.

`weekly_plans` remains only as a storage and publishing container when the product groups daily cards by Monday-anchored week. It is not a generation unit.

Historical note: full-week parallel generation existed on branch `archive/full-week-parallel-generation` and is documented in `docs/day-at-a-time-pivot-brief.md`.

## Brand Personality

Calm, prepared, editorial, practical, and personal.

The product should feel like a premium fitness journal with operational precision behind it. Creator-facing tone is warm and reassuring. Manager-facing tone is concise, source-aware, and controlled.

## Anti-references

Do not make the app feel like a generic AI chatbot, analytics dashboard, growth-hacking tool, SaaS content calendar, or dense CRM.

Avoid streak pressure, "viral trend detected" language, engagement-optimization copy, weight-loss framing, guilt, extreme fitness claims, politics, negativity, and over-polished advice.

Avoid exposing backend/schema terms such as `trend_observation`, `content_pattern`, `audio_candidate`, or `daily_card_reference`. Use product language: Reference, Trend, Pattern, Audio Option, Idea, Daily Card, Brand Brief, and Key Moment.

## Design Principles

1. Shootability wins over trend potential.
2. Daily Mode is the home base; strategy and setup stay behind admin controls.
3. AI actions create drafts or alternatives; humans confirm before publish.
4. Published cards are stable and changes are explicit, explainable, and safe.
5. Skipped or low-energy days should still produce a useful action, not a sense of failure.

## Accessibility & Inclusion

Target native iPhone ergonomics first, with touch targets that are comfortable for repeated daily use. Preserve clear focus states, readable contrast, reduced-motion compatibility, and text that remains legible in compact iPhone layouts.

Creator-facing language should be low-pressure and inclusive. Completion means a decision was made, not that content was necessarily posted.
