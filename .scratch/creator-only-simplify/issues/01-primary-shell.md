# Primary shell without Manager mode

Type: grilling
Status: resolved

## Question

What exact primary navigation does the Creator-only app use — tabs, Profile contents, and how the Creator enters Plan — once Manager/Admin mode is gone?

Constraints already locked: primary surfaces are Today, Shoot Folio, Other ideas, Archive, Profile; Plan is buried (not a peer mode); no Manager shell.

## Answer

**Root tabs (order):** Today · Archive · Profile.

**Flows off Today (not tabs):**
- Shoot Folio — navigation push from the Today card
- Other ideas — existing sheet/control on Today (“Give me other ideas”), not inside overflow
- Plan when a card is showing — only via Today `⋯` overflow; menu contains **Plan only**
- Plan when Today is empty — **CTA only** (single empty-state action into Plan); no `⋯` on empty Today

**Profile contains:**
- Account (identity + sign out)
- One **Plan** entry into the buried Plan hub
- Light support: Supabase status and Gemini status
- No Manager tools, no nested Archive, no Creator Profile editor, no References on Profile

**Plan entry points (exactly three):**
1. Profile → Plan
2. Empty Today → primary CTA
3. Today with card → `⋯` → Plan

**Not in this shell:** Plan tab, Manager/Admin mode switch, Archive nested under Profile.

**Hand-off to Plan hub IA:** Daily generation prompt is first in Plan; Creator Profile editor and References are collapsible accordion sections below that prompt (to be detailed in ticket 02).
