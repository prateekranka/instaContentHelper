# PROTOTYPE — Today UI directions

Throwaway exploration. **Do not ship.**

## Question

What should Creator **Today** feel like if we abandon the current cream / serif / oxblood editorial journal system?

## Run

```bash
open prototypes/today-ui/index.html
# or
python3 -m http.server 8765 --directory prototypes/today-ui
# then http://localhost:8765/?v=1
```

Flip with the bottom picker, `←`/`→`, `1`–`3`, or `R` to replay entrance motion.

## Variants

| # | Variant | Axis | When it wins | Cost |
| --- | --- | --- | --- | --- |
| 1 | Night Deck | Layout + personality — immersive media-first | Daily open should feel like “start the shoot,” not read a journal | Less editorial warmth; weaker for empty/missing states |
| 2 | Call Sheet | Density + IA — production list, no hero | Creator wants cues and package copy in one scannable sheet | Least brandable; can feel cold/ops-heavy |
| 3 | Soft Coach | Hierarchy + interaction — brief + accordion folio | Reassurance and low pressure matter more than spectacle | Eats vertical space; accordion hides package depth |

Selection persists via `?v=1|2|3`.
