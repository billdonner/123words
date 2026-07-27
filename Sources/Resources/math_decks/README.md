# Math decks imported from cardzerver — 2026-06-04

12 decks / 764 cards extracted from the cardzerver `decks` table (kind=`flashcard`, titles matching `addition|subtraction|visual`). Owned by 123words from here on — qross/cardzerver will keep them quarantined as `moved_to_123words` once we confirm this import is wired up here.

## Source data shape

Each card row in `cardzerver_export_2026-06-04.json`:

```json
{
  "deck_id":   "<uuid>",
  "deck_title":"Addition 0-5",
  "card_id":   "<uuid>",
  "position":  0,
  "question":  "0 + 0 = ?",
  "answer":    "0",
  "topic":     "..."
}
```

## Deck inventory

| Deck | Cards |
|------|-------|
| Addition 0-5 | 30 |
| Addition 0-10 | 121 |
| Addition 2-Digit | 100 |
| Addition 3 Numbers | 100 |
| Addition 6-10 | 30 |
| Subtraction 0-5 | 30 |
| Subtraction 0-10 | 66 |
| Subtraction 2-Digit | 100 |
| Subtraction 6-10 | 30 |
| Visual Addition 0-5 | 36 |
| Visual Addition 3 Numbers | 100 |
| Visual Subtraction 0-5 | 21 |
| **TOTAL** | **764** |

## Why here

cardzerver hosts qross's trivia corpus. These math flashcards leaked into the same DB because the schema is shared, but they have no qross consumer — the picker filters them out, and 123words has its own `MathCardStore`. Moving them to this repo means:

- cardzerver can quarantine + eventually hard-delete them without losing data
- 123words owns the source of truth for math content alongside `Sources/math_cards.json`
- Future math curation happens in this repo, not in the qclean pipeline

## Wiring (TODO when 123words next iterates math)

The existing `MathCardStore.MathCard` shape is `{kind, q, a}` with rendered visual hints (`"1 + 3 = ?\n🔵 🔴🔴🔴"`). The cardzerver export has plain `question` / `answer` strings — you'll want to either:

1. Convert the export into `MathCard`-compatible JSON and append to `math_cards.json`, or
2. Add a second loader (`CardzerverMathStore`) that uses the export directly.

Pick whichever is closer to how 123words wants to surface these grades.
