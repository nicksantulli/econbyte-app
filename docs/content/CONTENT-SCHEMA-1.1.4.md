# EconByte 1.1.4 content contract — packs, courses, Daily Brief

Everything below is machine-checked by `scripts/validate_content.mjs` (a Node mirror of the
Swift validators and `EconByteTests`). Run it before handing content over:

```
node scripts/validate_content.mjs packs   <file> --fragment --net
node scripts/validate_content.mjs courses <file> --fragment --net
node scripts/validate_content.mjs brief   <file> --net
```

`--net` resolves every cited URL. Hosts that refuse this box (bls.gov, sec.gov return 403 to
non-browser clients) are reported as UNVERIFIABLE — verify those with a browser-class fetch and
record the retrieval date; never cite a page you have not seen.

## House rules (all three content types)

- **Educational, not advice.** Teach mechanisms. Never tell the reader what to buy, sell, or hold;
  never predict a price or a rate; never name a security, fund company, brokerage, or trademarked
  index (say "a broad U.S. stock index", not a brand). The validator bans a phrase list
  (`should buy`, `invest in`, `we recommend`, `beat the market`, `will rise`, …) and a brand list.
- **Primary sources only.** Every card and lesson cites a public primary source from the approved
  host list in the validator (federal agencies, Reserve Banks, Treasury, SEC/investor.gov, CFPB,
  FDIC, CBO, IMF, World Bank, OECD, BIS, ECB, Bank of England, ONS, Eurostat, StatCan, archives.gov,
  loc.gov, federalreserveeducation.org). `https`, no query string, no fragment, a real document
  title, `publicationDate` ≤ `verificationDate` = the catalog's `verifiedOn` (2026-09-14).
  `datePrecision` ∈ `stated-on-page` | `observed-last-modified` | `observed-on-verification-date`.
- **Plain English.** Short sentences. Define every term the first time it appears. A reader with
  no finance background should follow every paragraph.
- **No stale wording**: never `currently`, `today`, `recently`, `this year`, `last year`,
  `right now`, `nowadays`, `at present`, `these days`, `as of now`. State the period instead
  ("in 2008", "between 1973 and 1982").
- **No year later than 2026** anywhere in the prose.
- **Disclaimer** string, verbatim, wherever the schema asks for one:
  `Educational content only. EconByte does not provide financial, investment, or tax advice.`
- Original writing. Do not copy sentences from sources; restate facts in our own words.

## Packs (`packs-v1.json` — exact `curriculum-v1.1.json` card schema)

A pack = 4 topics × 8 cards. Card ids are `<prefix>-001 … -008` where `<prefix>` is unique per
topic across the whole app (core prefixes in use: cb cs dd ei fp fx gdp hm inf ir lm rec sd tax tt;
pack prefixes in use: cr fdv hb mk rr sb sn sr). Topic ids must not collide with core topics
(`inflation interest-rates gdp supply-demand labor-markets trade-tariffs housing-market central-banks
recessions debt-deficits exchange-rates consumer-spending taxes fiscal-policy economic-indicators`)
or with the shipped pack topics (`stocks-bonds funds-diversification risk-return market-structure
household-budgets credit-borrowing saving-retirement safety-nets`).

```json
{
  "packID": "history",
  "name": "Economic History",
  "productID": "com.nsantulli.econbyte.pack.history",
  "icon": "clock.arrow.circlepath",
  "summary": "One or two sentences.",
  "topics": [
    {
      "topicID": "tulip-south-sea", "name": "Tulip Mania & the South Sea Bubble", "icon": "leaf",
      "order": 1, "access": "pack", "summary": "One or two sentences.",
      "cards": [
        {
          "cardID": "tsb-001", "topicID": "tulip-south-sea",
          "title": "…", "definition": "≥ 60 chars, plain English",
          "example": "≥ 40 chars, MUST contain at least one digit (a date, a count, an amount); must not restate the definition",
          "disclaimer": "Educational content only. EconByte does not provide financial, investment, or tax advice.",
          "difficulty": "intro | intermediate | advanced   (each topic: ≥1 intro; aim 3 intro / 4 intermediate / 1 advanced)",
          "source": {"organization": "…", "documentTitle": "…", "url": "https://…", "publicationDate": "YYYY-MM-DD", "datePrecision": "stated-on-page", "verificationDate": "2026-09-14"},
          "editorial": {"status": "verified", "reviewer": "EconByte editorial review (Dudley Development)"},
          "claim": {"units": "…", "geography": "…", "claimKind": "observation | illustration", "observationPeriod": "…", "retrievalDate": "2026-09-14"}
        }
      ]
    }
  ]
}
```

`claim` is REQUIRED whenever the prose states a magnitude (`$…`, `N percent`, `N million/billion/
trillion`) and optional otherwise. `observation` = a dated reading reproducible from the cited page —
`observationPeriod` must name a year. `illustration` = worked arithmetic that teaches the mechanism —
`units` must contain the word `illustrative`. Never present an illustration as a statistic.

The four 1.1.4 packs and their productIDs (fixed):

| packID | name | productID |
|---|---|---|
| `history` | Economic History | `com.nsantulli.econbyte.pack.history` |
| `world` | Economies Around the World | `com.nsantulli.econbyte.pack.world` |
| `systems` | Economic Systems | `com.nsantulli.econbyte.pack.systems` |
| `personalfinance` | Personal Finance | `com.nsantulli.econbyte.pack.personalfinance` |

A writer's draft file is `{"schemaVersion":1,"catalogVersion":"1.1.4-packs-1","verifiedOn":"2026-09-14",
"disclaimer":"<canonical>","editorialPolicy":"<copy from packs-v1.json>","packs":[ …one or two packs… ]}`
validated with `--fragment`.

## Courses (`courses-v1.json`)

```json
{
  "schemaVersion": 1, "catalogVersion": "1.1.4-courses-1", "verifiedOn": "2026-09-14",
  "disclaimer": "<canonical>",
  "educationalNotice": "Educational content only — not investment advice. Nothing here recommends any investment or predicts any price.",
  "editorialPolicy": "…≥ 80 chars…",
  "courses": [
    {
      "courseID": "investing-approaches", "title": "Investing Approaches", "icon": "chart.pie.fill",
      "summary": "…", "level": "intro | intermediate", "estimatedMinutes": 35,
      "lessons": [
        {
          "lessonID": "ia-01", "title": "…", "summary": "…", "estimatedMinutes": 6,
          "isPreview": true,            // exactly the FIRST lesson of each course is true (free preview)
          "blocks": [ … ],
          "sources": [ { same shape as a card source } ]   // ≥ 1
        }
      ]
    }
  ]
}
```

Course ids and lesson prefixes are fixed: `investing-approaches`/`ia-NN`, `reading-price-charts`/`rpc-NN`,
`bonds-rates-yield-curve`/`bry-NN`. Each course ≥ 5 lessons (aim 6). Each lesson: ≥ 5 blocks, ≥ 1 `chart`
or `diagram`, exactly 1 `quiz`, ≥ 1 `paragraph`, the LAST block is `takeaways`, and paragraph+callout
prose totals ≥ 600 characters (aim 900–1,600).

Block types:

| type | fields |
|---|---|
| `paragraph` | `text` (≥ 80 chars) |
| `callout` | `style` ∈ `note`/`caution`/`example`, `title`, `text` |
| `keyTerms` | `terms`: 2–6 × `{term, definition ≥ 30 chars}` |
| `diagram` | `diagramID` ∈ `candle-anatomy` `risk-return-ladder` `diversification-basket` `price-yield-seesaw` `yield-curve-shapes` `allocation-pie` `support-resistance` `fee-drag` `trend-channel`; `caption` |
| `chart` | `chartID` (unique), `kind` ∈ `candlestick`/`line`/`bar`, `title`, `caption`, `xLabel`, `yLabel`, `dataNote` (MUST start with "Synthetic"), and data (below); optional `markers: [{x, label}]` |
| `quiz` | `question`, `choices` (3–4, distinct), `answerIndex`, `explanation` (≥ 40 chars) |
| `takeaways` | `items` (2–5 strings) |

Chart data: `candlestick` → `candles: [{x, open, high, low, close}]` (8–60, x increasing, high ≥ max(open,
close), low ≤ min). `line`/`bar` → `series: [{name, points: [{x, y}]}]` (1–4 series, 2–60 points). All
series are **synthetic, hand-designed illustrations** — invent smooth, plausible numbers that show the
mechanism; never paste real prices. Say so in `dataNote`, e.g. `Synthetic illustration — not real market data.`

What the app draws for each diagram id (write captions that match):
`candle-anatomy` — one candle labelled open/high/low/close, body and wicks; `risk-return-ladder` — steps from
cash/T-bills to bonds to stocks with rising expected return and rising variability; `diversification-basket`
— one basket of one egg vs. many baskets, a shock hits one; `price-yield-seesaw` — a seesaw: price up, yield
down; `yield-curve-shapes` — normal, flat, inverted curves side by side; `allocation-pie` — an illustrative
mix labelled "illustrative" with no percentages implied as advice; `support-resistance` — a price path
bouncing between two horizontal bands; `fee-drag` — two growth paths diverging as an annual fee compounds;
`trend-channel` — an up-sloping channel with higher highs and higher lows.

## Daily Brief (`brief-sample.json` and `latest.json`)

```json
{
  "schemaVersion": 1, "briefDate": "2026-09-14", "publishedAt": "2026-09-14T12:00:00Z", "isSample": true,
  "headline": "…", "sections": [
    {"type": "released", "title": "What was released", "items": [
      {"title": "…", "releaseDate": "2026-09-11", "summary": "plain-English what it says", "meaning": "plain-English why it matters",
       "figures": [{"label": "…", "value": "…"}],
       "source": {"organization": "…", "documentTitle": "…", "url": "https://www.bls.gov/…", "retrievedAt": "2026-09-14T…Z"}}]},
    {"type": "scheduled", "title": "Scheduled this week", "items": [{"date": "2026-09-16", "title": "…", "organization": "…", "url": "https://…"}]},
    {"type": "concept", "title": "One concept to know", "conceptTitle": "…", "text": "…", "linkedCardID": "inf-001"}
  ],
  "disclaimer": "…not investment advice…", "methodology": "…primary sources only…"
}
```

Only hosts in `BRIEF_HOSTS` (official releases + open-licence statistical offices). No news sites, ever.
No predictions, no recommendations, no named securities.
