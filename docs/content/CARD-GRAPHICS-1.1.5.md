# EconByte 1.1.5 — card graphics contract

Every card in `EconByte/Resources/curriculum-v1.1.json` (180) and `EconByte/Resources/packs-v1.json`
(288) may carry one optional `graphic` object. The app draws it natively (SwiftUI and Swift Charts, no
image assets) on the concept face of the card, between the title and the definition
(`EconByte/Views/Graphics/CardGraphicView.swift`). Nothing else about the card changes.

Machine checks live in two places, which must agree:

- `scripts/card_graphics.mjs`: the content checker. It resolves data recipes, recomputes formulas, and
  compares every number in a graphic with the card's own prose.
- `EconByteTests/CardGraphicsTests.swift`: the build-time gate. It covers decoding, structure, symbols,
  accessibility summaries, and a smoke render of every kind.

```
node scripts/card_graphics.mjs check                  # every graphic in both catalogs
node scripts/card_graphics.mjs check --require-all    # …and fail if any card has none
node scripts/card_graphics.mjs check-fragment <file>  # a draft {cardID: spec} file
node scripts/card_graphics.mjs resolve-fragment <file># fill recipe/compute series into a draft
node scripts/card_graphics.mjs merge <file>...        # insert drafts into the catalogs (additive text edit)
node scripts/card_graphics.mjs stats | dump [ids…]
```

## Accuracy rules (these override everything else)

1. **No number may appear without a basis.** Every graphic declares one `basis`:

   | basis | Meaning | Numbers allowed | Footnote the app prints |
   |---|---|---|---|
   | `conceptual` | A picture of a mechanism or of a set of named parts | **none**: no digit anywhere in the graphic | none |
   | `fromCard` | Restates figures the card's prose already states (already audited against the card's source) | Only numbers that appear in the card's title, definition or example, or that are declared in `derived` | "Figures from this card's source" |
   | `computed` | A series computed exactly from a stated formula (`compute`) | Compute inputs must appear in the card text. Other numbers must be in the card, in `derived`, or in the computed output | "Computed from this card's figures" |
   | `sourced` | Real data pulled by recipe from FRED or the World Bank | Card numbers, `derived`, or the resolved data | "Source: {organization}, {period}" |
   | `illustrative` | Invented shapes or numbers that teach a mechanism | Anything, but see rule 3 | "Illustrative, not real data" |

2. **Never type a data series by hand.** Real series come only from a `recipe` (FRED or World Bank),
   which the script resolves. Formula series come only from `compute`. Hand-typed numbers are allowed
   only for `fromCard` values (checked against the prose), `derived` values (checked by arithmetic),
   and `illustrative` graphics.
3. **An illustrative graphic must never contradict the card.** If the card states a figure, reuse it
   (`fromCard` or `computed`) rather than inventing a different one. If a card's own example is
   illustrative (its `claim.claimKind` is `illustration`), restating those figures is `fromCard`.
4. **A graphic may not add a fact the card does not state** unless it is `sourced`. Examples: a date
   not in the prose, a country ranking, a name. Captions and labels restate; they do not extend.
5. **If the card text looks wrong, do not change it in a graphic draft.** Record a flag for the phase
   lead, who verifies against the primary source and logs any text fix in the sources file.
6. The house rules still apply to graphic text:
   - no advice framing;
   - no stale wording (`currently`, `today`, `recently`, …);
   - no year after 2026;
   - no brand, security or trademarked index names;
   - US spelling.

### `derived`

`"derived": [{"value": 7.65, "expr": "6.2 + 1.45"}]`

- `expr` allows numbers, `+ - * / ^ ( )`, and nothing else.
- Each number literal must appear in the card text or be one of the constants
  `1 2 4 10 12 52 100 365 1000`.
- `value` must equal the evaluated `expr` within 0.5% (or ±0.05).
- A derived value may then be used anywhere in the graphic.

### `compute` (series for `line` only)

Put the recipe on the series (`line.series[i].compute`). The script writes the points and the checker
recomputes them. Inputs are plain numbers. For a single computed value (a bar, a label), use `derived`
instead.

| model | Inputs | Output points `[x, y]` |
|---|---|---|
| `compound` | `principal, ratePct, years, step` (optional `contribution` per year at year end, optional `periodsPerYear` default 1) | `[t, balance]`, t = 0, step, …, years |
| `simple` | `principal, ratePct, years, step` | `[t, principal·(1 + r·t)]` |
| `purchasingPower` | `start, ratePct, years, step` | `[t, start / (1+r)^t]` |
| `amortizationBalance` | `principal, aprPct, months, step` | `[m, remaining balance after payment m]` |
| `amortizationInterestShare` | `principal, aprPct, months, step` | `[m, % of payment m that is interest]` (m starts at 1) |

All outputs are rounded to 2 decimals.

### `recipe` (series for `line` with basis `sourced`)

```json
{"provider": "fred", "series": "CPIAUCSL", "transform": "pct_change_12m",
 "sample": "annual_mean", "from": "2015-01", "to": "2025-12", "decimals": 1}
```

- `provider`: `fred`, which uses `https://fred.stlouisfed.org/graph/fredgraph.csv?id=…`.
- `transform`: `level`, `pct_change_12m` (monthly data), `pct_change_4q` (quarterly data), or
  `pct_change_1y` (annual data).
- `sample`:
  - `all`: every observation; x = year + (month−1)/12;
  - `annual_mean`: the calendar-year mean, which needs 12 monthly or 4 quarterly observations;
  - `month:MM`: that month's value each year;
  - `year_end`: the last observation of each year.

  For every sample except `all`, x is the year.
- `from` and `to` are inclusive `YYYY-MM` bounds, applied after the transform. `decimals` is 0–3.

```json
{"provider": "worldbank", "indicator": "SI.POV.DDAY", "country": "WLD", "from": 1990, "to": 2022, "decimals": 1}
```

`worldbank` uses `https://api.worldbank.org/v2/country/{country}/indicator/{indicator}`. Missing years
are dropped, never interpolated.

A `sourced` graphic must carry
`"source": {"organization", "title", "url", "period", "retrieved"}`:

- `url` is the human page on an approved host: `https://fred.stlouisfed.org/series/ID` or
  `https://data.worldbank.org/indicator/ID?locations=…` without the query, so
  `https://data.worldbank.org/indicator/ID`;
- `period` reads like "2015–2025, annual average";
- `retrieved` is `2026-09-15`.

Every sourced graphic is also listed in `docs/content-audit/2026-09-15-card-graphics-sources.md`.

## Spec shape

Common fields:

```json
{
  "kind": "bars | line | diagram | flow | compare | timeline | formula | proportion | icons",
  "title": "≤ 56 characters, sentence case, no final period",
  "basis": "conceptual | fromCard | computed | sourced | illustrative",
  "note": "optional, ≤ 90 characters, printed under the graphic",
  "source": { … only for sourced … },
  "derived": [ … optional … ],
  "<kind>": { … exactly one payload, named after the kind … }
}
```

VoiceOver summaries are generated by the app from the payload, so there is no field to write for
them. Keep labels short: the graphic is about 320 pt wide on an iPhone.

### `bars` — horizontal labelled bars (2–6 items)

```json
"bars": {"unit": {"prefix": "$", "suffix": ""}, "decimals": 0,
         "items": [{"label": "Social Security", "value": 6.2, "display": "6.2%", "emphasis": false}]}
```

- `label` ≤ 26 characters.
- `display` is optional and overrides the formatted value (≤ 16 characters).
- Values must be ≥ 0 and share one unit. Never put percentages and dollars in the same bars.
- Set `emphasis: true` on at most 2 items.

### `line` — Swift Charts line (1–3 series, 2–60 points each)

```json
"line": {"xLabel": "Year", "yLabel": "Percent", "xFormat": "year | month | number",
         "unit": {"prefix": "", "suffix": "%"}, "decimals": 1,
         "series": [{"name": "CPI, 12-month change", "points": [[2019, 1.8]], "recipe": {…} | "compute": {…}}],
         "markers": [{"x": 2022.42, "label": "Jun 2022"}], "references": [{"y": 2, "label": "2% goal"}]}
```

- `xFormat: month` takes x = year + (month−1)/12.
- x values strictly increase within a series.
- Up to 2 markers and 2 references. Marker and reference labels are ≤ 18 characters.

### `diagram` — schematic plot in unit space (always `conceptual` or `illustrative`)

```json
"diagram": {"xLabel": "Quantity", "yLabel": "Price",
  "curves": [{"label": "Demand", "points": [[0.1,0.9],[0.9,0.1]], "style": "solid|dashed", "tone": "primary|accent|muted"}],
  "dots": [{"x": 0.5, "y": 0.5, "label": "Equilibrium"}],
  "guides": [{"axis": "x|y", "at": 0.5, "label": "P*"}],
  "arrows": [{"from": [0.5,0.2], "to": [0.7,0.2], "label": "Shift"}]}
```

- Coordinates are in [0, 1], with the origin at the bottom left.
- Limits: 1–4 curves (2–12 points each), up to 3 dots, 3 guides, and 2 arrows.
- Curves with 3 or more points are drawn smoothed.
- The curve label sits at the last point. Labels are ≤ 18 characters.
- Axis labels carry no numbers.

### `flow` — boxes and arrows

```json
"flow": {"layout": "chain | cycle", "steps": [{"title": "Fed raises its rate target", "detail": "optional"}]}
```

- A chain has 2–4 steps, drawn top to bottom with arrows; a 4-step chain carries no details (it would
  be too tall for the card). A cycle has 3–4 steps arranged in a loop.
- `title` ≤ 34 characters. `detail` ≤ 48 characters; details are omitted in a cycle.

### `compare` — 2 or 3 columns × 2–4 rows

```json
"compare": {"columns": ["Traditional", "Roth"],
            "rows": [{"label": "Taxed", "values": ["On withdrawal", "On contribution"]}]}
```

- Column heads ≤ 16 characters.
- Row `label` ≤ 16 characters. Each value ≤ 24 characters.
- A row's `label` may be `""` when the columns speak for themselves.

### `timeline` — 2–5 dated events, oldest first

```json
"timeline": {"events": [{"when": "Aug 15, 1971", "label": "Gold window closes"}]}
```

- `when` ≤ 14 characters and contains a four-digit year, optionally a month (`Jan`–`Dec`, or the
  full name) and a day. Events must be in non-decreasing date order.
- `label` ≤ 40 characters.

### `formula` — an equation with its terms

```json
"formula": {"expression": "GDP = C + I + G + (X − M)",
            "terms": [{"symbol": "C", "meaning": "Consumer spending"}],
            "example": "optional worked line, ≤ 60 characters"}
```

- `expression` ≤ 40 characters. Use `×` `÷` `−`.
- 1–5 terms. `symbol` ≤ 8 characters, `meaning` ≤ 32 characters.

### `proportion` — share of a whole

```json
"proportion": {"style": "bar | waffle", "total": 100, "unitLabel": "of every 100 households",
               "segments": [{"label": "Collectivized", "value": 97}], "remainderLabel": "Other"}
```

- 1–4 segments. Values must be ≥ 0 and their sum ≤ `total`.
- The remainder is drawn, and must be labelled with `remainderLabel`, whenever sum < total.
- `waffle` needs `total` ∈ {10, 20, 50, 100} and integer values.
- Labels are ≤ 22 characters. `unitLabel` is ≤ 34 characters.

### `icons` — a few named parts joined by a connector

```json
"icons": {"connector": "plus | arrow | versus | equals | none",
          "items": [{"symbol": "house", "label": "Collateral"}]}
```

- 2–4 items; labels ≤ 18 characters.
- `symbol` must be an SF Symbol that exists on iOS 16; the build-time test checks this. Stick to the
  list below.
- Use icons only when a card has no honest chart, flow, comparison or timeline. Every `icons` graphic
  is logged in the report.

Known-good symbols:
`dollarsign.circle banknote creditcard building.columns building.2 house car cart bag briefcase person
person.2 person.3 hammer wrench.and.screwdriver gearshape leaf drop flame bolt globe globe.americas
globe.europe.africa globe.asia.australia shippingbox airplane ferry chart.bar chart.line.uptrend.xyaxis
chart.line.downtrend.xyaxis chart.pie percent arrow.up arrow.down arrow.left.arrow.right
arrow.triangle.2.circlepath clock calendar hourglass lock lock.open key shield checkmark.shield
exclamationmark.triangle doc.text signature scalemass hand.raised fork.knife cross.case stethoscope heart
graduationcap book newspaper phone envelope iphone eurosign.circle yensign.circle sterlingsign.circle
list.bullet magnifyingglass eye flag map tag gift star crown sun.max cloud.rain thermometer
person.crop.circle.badge.checkmark lightbulb scissors tray.full archivebox calendar.badge.clock
building.columns.fill textformat.123 function`

## Choosing a kind

- The card compares two or three things on the same attributes: use `compare`.
- The card describes a sequence or causal chain: use `flow` with `chain`. A loop (a business cycle, a
  circular flow): use `flow` with `cycle`.
- The card is about dates in history: use `timeline`, with dates taken from the card.
- The card states several same-unit figures: use `bars` (`fromCard`).
- The card is about a share of a whole: use `proportion`.
- The card defines a ratio or identity: use `formula`.
- The card is about growth over time from a rate: use `line` with `compute`.
- The card is about a curve-shaped mechanism (supply and demand, a price ceiling, a yield curve shape,
  the Phillips curve): use `diagram`.
- The card cites a FRED or World Bank series and a short history adds real context: use `line` with
  `sourced`. The resolved values must agree with any figure the card states for the same period.
