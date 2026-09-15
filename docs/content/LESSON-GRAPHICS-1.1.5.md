# EconByte 1.1.5 — graphics in the Pro story lessons (Phase 24)

Owner, after testing 1.1.5 (20): "for Econ continue improving the new lessons/courses under pro with additional
graphics and tightening up the UI."

Story lessons (`docs/content/STORY-SCHEMA-1.1.5.md`) now carry the same typed, natively drawn graphics as the
flip cards (`docs/content/CARD-GRAPHICS-1.1.5.md`). There is one spec, one renderer
(`EconByte/Views/Graphics`) and one checker (`scripts/card_graphics.mjs`). Lessons add a visual type, a basis, a
kind, a proportion style, a compute model and a centerpiece flag. Everything in the card contract applies
unless this page says otherwise.

```
node scripts/lesson_graphics.mjs dump <lessonID|courseID>          # beats, numbered, with their pictures
node scripts/lesson_graphics.mjs check-fragment <draft.json>       # a draft against the lessons it touches
node scripts/lesson_graphics.mjs resolve-fragment <draft.json>     # fill compute (and FRED recipe) points
node scripts/lesson_graphics.mjs merge <draft.json>...             # write courses-v1.json (visual/centerpiece only)
node scripts/lesson_graphics.mjs check                             # the whole catalog: 0 errors required
node scripts/validate_content.mjs courses EconByte/Resources/courses-v1.json
```

## 1. The `graphic` visual

```json
{"kind": "idea", "text": "…", "visual": {"type": "graphic", "graphic": { …CardGraphicSpec… }}}
```

- Any idea, term or check beat may carry one. A recap never carries a picture.
- The graphic's labels are artwork, like a chart's axis: they are not counted in the beat's 35 words. Per-label
  character limits from the card contract bound them.
- `icons` is not used in lessons. If a beat has no honest picture, it gets none.
- VoiceOver reads the summary generated from the payload (`CardGraphicSpec.accessibilitySummary`), so there is
  nothing to write for it.

## 2. Basis in a lesson

| basis | In a lesson | Footnote in the app |
|---|---|---|
| `fromLesson` | Restates figures the lesson's own prose states (title, summary, any beat, chart titles and captions). Every number must be there, or in `derived` over lesson numbers. | "Figures from this lesson" |
| `computed` | A `line` series computed exactly by `compute`; inputs appear in the lesson prose (or `derived`) | "Computed from this lesson's figures" |
| `sourced` | A `line` series resolved by a FRED / World Bank `recipe`, with `source` | "Source: {organization}, {period}" |
| `illustrative` | Invented shapes that teach a mechanism, and must never contradict the lesson | "Illustrative, not real data" |
| `conceptual` | No digits anywhere | none |

`fromCard` is rejected in a lesson, and `fromLesson` is rejected on a card.

**Agreement.** A graphic must say what its beat says. The checker warns when a printed figure is stated
elsewhere in the lesson but not on this beat or the one before it. Every warning is read and resolved by the
writer (usually by showing the figure where the text states it).

**Sourced data in lessons.** Until 1.1.5, every lesson chart was synthetic. A sourced graphic may now plot a
real public series (for example a Treasury yield spread from the Federal Reserve Board via FRED) when real
history makes the beat's point better than a drawing. It must agree with any figure the lesson states. It
carries no forecast language, and the markers name only past, dated events.

## 3. New kind: `candles`

A textbook candlestick drawing, for the Reading Price Charts course.

```json
"candles": {
  "xLabel": "Trading day", "yLabel": "Price",
  "candles": [{"open": 97.6, "high": 97.9, "low": 95.2, "close": 97.8}],
  "highlight": {"from": 6, "to": 6, "pattern": "hammer", "label": "Hammer"},
  "annotate": "ohlc",
  "references": [{"y": 104, "label": "Resistance"}]
}
```

- 1–30 candles, each with `high ≥ max(open, close)`, `low ≤ min(open, close)` and `high > low`.
- Drawn as in the lesson charts and on most platforms' dark themes:
  - a candle that closes above its open (**up**) is sky blue;
  - a candle that closes below its open (**down**) is amber;
  - a thin wick spans the low to the high;
  - the body spans the open and the close.

  A legend under the drawing says which colour is which, so no reader needs to know a green/red convention.
- `basis` is `illustrative`, or `fromLesson` when the lesson states every price.
- `highlight` (optional) marks 1-based positions `from`…`to` and names them. `pattern` is checked geometrically
  (`candleProblems` in `scripts/card_graphics.mjs`, mirrored in Swift):

  | pattern | Definition the drawing must satisfy |
  |---|---|
  | `none` | Just a labelled span (for example "Breakout") |
  | `doji` | body ≤ 10% of the range |
  | `hammer` | after a decline (the close before it is below the close 3 candles before it); body > 0; lower wick ≥ 2 × body; upper wick ≤ 10% of the range |
  | `shootingStar` | the mirror image after a rise: upper wick ≥ 2 × body; lower wick ≤ 10% of the range |
  | `bullishEngulfing` | after a decline, a down candle and then a larger up candle whose body covers the whole first body |
  | `bearishEngulfing` | the mirror image after a rise |

  The label must name the pattern ("Hammer", "Bullish engulfing", …).
- `annotate: "ohlc"` labels Open, High, Low and Close on a single highlighted candle (anatomy beats).
- Up to 2 `references`: horizontal lines such as support or resistance.
- House rule: a pattern graphic describes past prices only. Its title and labels never say what happens next.

## 4. Additions shared with the card contract

- `proportion.style: "donut"`: a ring with a legend. The same rules as `bar` apply (segments ≤ total, and a
  labelled remainder).
- `compute.model: "returnPath"`, which compounds a value through stated period returns:
  `{"model": "returnPath", "start": 100, "returnsPct": [50, -50]}` → `[[0,100],[1,150],[2,75]]`. The magnitude of
  every return and the start must be stated in the lesson (or be `derived`).

## 5. Centerpiece

Exactly one beat per lesson carries `"centerpiece": true`. It is the lesson's key concept, drawn as a strong
picture.

- **Beat kind:** the beat is an idea or a term.
- **Picture:** a lesson `chart`, a `diagram`, or a graphic of kind `line`, `bars`, `candles`, `diagram`,
  `proportion` or `timeline`.
- **In the app:** the centerpiece is drawn taller than other pictures.
- **Where it is enforced:** the Node validator and the unit tests require exactly one. The runtime catalog
  validator accepts at most one, so a content slip can never lock readers out of Pro.

## 6. Coverage

- **Teaching beats** are idea and term beats.
- A teaching beat is covered when it carries a purposeful picture: any visual except a decorative `symbol`.
- **Target:** ≥ 90% across the catalog and ≥ 80% in every lesson, enforced by `validate_content.mjs courses` and
  `StoryLessonsTests`.
- **Checks and recaps** are outside the count.
- **Symbols** stay allowed, but they do not count.

Prefer a specific picture to repeating the same chart on many beats. The checker warns at 4 in a row.

## 7. Fragments and the sources log

Writers never edit `courses-v1.json` directly; they write fragments:

```json
{"lessons": {"ia-06": {"1": {"visual": {"type": "graphic", "graphic": {…}}}, "16": {"centerpiece": true}}},
 "notes": {"ia-06/1": "What the picture shows and why it is right: the lesson figures used, the arithmetic, the source."}}
```

- A merge changes only `visual` and `centerpiece` on existing beats. It proves that before writing, and it
  refuses a catalog with errors.
- The sources log is generated from the merged catalog plus the fragments' notes:
  `node scripts/lesson_graphics.mjs sources-log docs/content-audit/2026-09-15-pro-course-graphics-sources.md <fragments>`.
- **If the lesson text looks wrong, a fragment does not change it.** The writer records it in `notes`, and the
  phase lead verifies it against the lesson's primary source.
