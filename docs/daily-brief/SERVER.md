# EconByte Daily Economic Brief — brief service

Status: **LIVE since 2026-09-15** (Lane B). Code: `~/Documents/GitHub/econbyte-brief-service` (README there covers
operations, the allow-list, the validator and manual runs). The iOS app (1.1.4) reads it through
`BriefStore.baseURL` — the one place the base URL is set.

## 1. What it is, and what it is not

- One JSON document per **U.S. federal business day** describing what official statistical and central-bank
  releases said, what is scheduled next, and one concept to know — plain-English sentences about public facts,
  with a link to every source and the time it was read.
- **Not an aggregator.** It never fetches, restates or is prompted with commercial news, wire services,
  newsletters, blogs or social posts.
- **No recommendations, no predictions, no named securities.** Every edition carries the disclaimer.

## 2. Allowed sources

Only URLs whose host is on the allow-list may be read or cited; anything else is a hard failure. The list is
mirrored in `DailyBrief.allowedHosts` (app), `BRIEF_HOSTS` in `scripts/validate_content.mjs`, and the service's
allow-list — change all three together. Publishers: BLS, BEA, Census, U.S. Treasury (home.treasury.gov,
fiscaldata, treasurydirect), Federal Reserve Board, FRED (permissively licensed series only), CBO, EIA, ECB, Bank of
England, Eurostat, ONS, Statistics Canada, IMF, World Bank, OECD, BIS. Redirects that leave the list are refused.

## 3. Schedule

- **11:30 America/New_York** — main pass; **17:30** — late pass, which publishes again only if new releases
  appeared that day (for example an FOMC statement), otherwise records "unchanged".
- U.S. federal business days only (weekends and OPM-observed federal holidays skipped). A failed pass retries every
  30 minutes, at most 3 attempts.
- On a day with no major scheduled release, the brief carries the most recent Treasury par yield curve posting,
  clearly dated.

## 4. How a brief is made

1. **Calendars (no model):** BLS, Census, Federal Reserve and BEA schedules.
2. **Release pages:** each of today's releases is mapped to its official page, which must prove it is that day's
   release (embargo line, release date) or it is skipped with an alert — never guessed.
3. **Facts:** verbatim sentences from each release's lead section, or lines built directly from the release's own
   table.
4. **Draft:** an AI model receives only those facts, the numbers each release allows, and candidate EconByte cards.
   It has no tools and returns structured JSON; each figure names the fact it came from.
5. **Publish gate (deterministic):** the app's `DailyBrief.validate` rules and `validate_content.mjs` rules; every
   URL on the allow-list and answering 200 in this run; every number in the text present in the item's facts in the
   same written form; headline and concept grounded in released facts and the linked card; the card id exists; no
   advice, prediction, stale-time or named-security wording.
6. **Fact-check:** a second, independent model pass checks every sentence and figure against the facts and cards;
   any issue fails the draft.
7. Up to 4 attempts; after that nothing is published, the previous brief stays, and an alert is sent.

## 5. Endpoints

| Path | Content |
|---|---|
| `/latest.json` | the newest published brief |
| `/index.json` | `{"schemaVersion": 1, "updatedAt", "dates": [...], "briefs": [{"briefDate", "headline", "isSample", "publishedAt", "url": "/archive/<date>.json"}]}` |
| `/archive/<YYYY-MM-DD>.json` | one brief per date |

Public JSON is served with `Access-Control-Allow-Origin: *` and `Cache-Control: public, max-age=300`.

**App behaviour:** fetch `latest.json` (at most hourly, or on pull to refresh), validate fail-closed, cache the
newest 30; then read `index.json` and cache up to 14 missing briefs, skipping any entry or document marked
`isSample` (the index also lists the app's bundled samples). Fetched briefs never show a SAMPLE badge. Offline, the
app shows the cache; only with no real brief on the device does it show the bundled samples, labelled SAMPLE.

## 6. Output schema (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "briefDate": "2026-09-15",
  "publishedAt": "2026-09-15T11:23:56Z",
  "isSample": false,
  "headline": "one sentence stating a fact from the day's releases",
  "sections": [
    {"type": "released", "title": "What was released", "items": [
      {"title": "…", "releaseDate": "YYYY-MM-DD", "summary": "…", "meaning": "…",
       "figures": [{"label": "…", "value": "…"}],
       "source": {"organization": "…", "documentTitle": "…", "url": "https://<allowed host>/…", "retrievedAt": "ISO-8601"}}
    ]},
    {"type": "scheduled", "title": "Scheduled this week", "items": [
      {"date": "YYYY-MM-DD", "title": "…", "organization": "…", "url": "https://<allowed host>/…"}
    ]},
    {"type": "concept", "title": "One concept to know", "conceptTitle": "…", "text": "…", "linkedCardID": "ir-005"}
  ],
  "disclaimer": "Informational only — not investment advice. …",
  "methodology": "… primary sources only …"
}
```

The app rejects a document that cites a host off the list, lacks the three sections, or has a disclaimer that does
not say it is not advice.
