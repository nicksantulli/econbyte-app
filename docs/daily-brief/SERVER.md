# EconByte Daily Economic Brief — server job specification

Status: SPEC (1.1.4 lane, 2026-09-14). The job is a follow-up lane; nothing here is built yet. The
iOS app (1.1.4) already consumes the output contract below and falls back to a bundled sample when
`latest.json` is missing, so the job can ship independently of an App Store release.

## 1. What it is, and what it is not

- One small JSON document per **U.S. business day**, describing what official statistical and
  central-bank releases said that day, what is scheduled for the rest of the week, and one concept
  to know, in our own plain-English sentences, with a link to every source and the time it was read.
- It is **not** an aggregator. The job never fetches, parses, summarizes, links to, or is prompted
  with any commercial news site, wire service, newsletter, blog, or social post. Facts come from the
  releases themselves. This is the legal basis of the product (see plan §2.2): U.S. government works
  are public domain; the other allowed publishers grant open reuse with attribution; every sentence
  we publish is our own expression about public facts, so there is no publisher copyright, no
  "hot news" exposure, and no licensing cost.
- It makes **no recommendations and no predictions**, names **no securities**, and prints the
  disclaimer on every edition (App Review 1.1 / 5.1; informational content only).

## 2. Allowed sources (the complete list — the app enforces the same list)

The job may read only URLs whose host is in this set. Anything else is a hard failure, not a fallback.

| Host | Publisher | Reuse terms |
|---|---|---|
| `www.bls.gov` | U.S. Bureau of Labor Statistics | U.S. government work, public domain |
| `www.bea.gov` | U.S. Bureau of Economic Analysis | public domain |
| `www.census.gov` | U.S. Census Bureau | public domain |
| `home.treasury.gov`, `fiscaldata.treasury.gov`, `www.treasurydirect.gov` | U.S. Treasury | public domain |
| `www.federalreserve.gov` | Federal Reserve Board | public domain |
| `fred.stlouisfed.org` | FRED (St. Louis Fed) — only series whose FRED page states public-domain/permissive terms (e.g. `DGS10`, `CPIAUCSL`, `UNRATE`); never a third-party-licensed series | per-series terms |
| `www.cbo.gov` | Congressional Budget Office | public domain |
| `www.eia.gov` | U.S. Energy Information Administration | public domain |
| `www.ecb.europa.eu` | European Central Bank | reuse permitted with attribution |
| `www.bankofengland.co.uk` | Bank of England | Open Government Licence |
| `ec.europa.eu` (Eurostat) | European Commission | reuse permitted with attribution |
| `www.ons.gov.uk` | UK Office for National Statistics | Open Government Licence |
| `www150.statcan.gc.ca`, `www.statcan.gc.ca` | Statistics Canada | Statistics Canada Open Licence |
| `www.imf.org`, `www.worldbank.org`, `www.oecd.org`, `www.bis.org` | international institutions | open terms with attribution; use only for scheduled-release calendars and headline figures |

Mirror of this list in code: `DailyBrief.allowedHosts` (app) and `BRIEF_HOSTS` in
`scripts/validate_content.mjs`. Change all three together.

**Market prices:** only end-of-day public reference data with permissive terms — the Treasury par
yield curve (`home.treasury.gov` daily yield curve) and permissive FRED series. No real-time quotes,
no exchange-licensed data, no index levels from index providers.

## 3. Schedule

- Railway cron service, project `dudley-growth` (same project as `vibe-rater-service`), one job.
- Runs at **17:30 America/New_York** on U.S. business days (Mon–Fri, skipping U.S. federal holidays
  per the OPM calendar). By then every 8:30 and 10:00 release is out and the Treasury yield curve
  for the day is posted. A second run at 20:30 ET republishes only if a source page changed
  (FOMC statement days, late corrections).
- Idempotent: the output key is the brief date; a re-run overwrites the same day's file.
- Time budget: ≤ 5 minutes; no retries beyond 3 per source; a source that cannot be read is
  **omitted with a note**, never guessed.

## 4. Pipeline

1. **Calendar step (deterministic, no model).** Read the BLS release schedule page for the month,
   the BEA schedule, the Fed FOMC calendar, and the Census economic indicators calendar. Produce the
   list of releases (a) published today, (b) scheduled for the remaining days of the current
   week plus the following Monday.
2. **Fetch step (deterministic).** For each release published today, GET its official summary page
   (`…/news.release/<x>.nr0.htm`, BEA release page, Fed press release). Record `retrievedAt`, the
   final URL after redirects, and the page text. Reject any redirect that leaves the allowed hosts.
3. **Extraction step (model, constrained).** Claude (Anthropic API; see `claude-api` skill for the
   current model id) receives ONLY the fetched release texts and a strict system prompt:
   - Extract the headline figures as `label`/`value` pairs exactly as the release states them
     (including seasonal-adjustment qualifiers and the reference period).
   - Write a 2–4 sentence `summary` ("what it says") and a 1–3 sentence `meaning` ("why it
     matters") in plain English, at a general-reader level, in our own words.
   - Never use the words/phrases in the banned lists (see §6). Never mention a company, a security,
     an index by trademark, or a price forecast. Never attribute a view to anyone.
   - Choose one `concept` of the day tied to one of today's releases and link it to an EconByte
     card id or lesson id from the catalog file supplied in the prompt (`curriculum-v1.1.json`,
     `packs-v1.json`, `courses-v1.json` ids — the job bundles these from the app repo at build time).
   - Output the JSON document in §5 and nothing else.
   The model has **no web tool and no search tool**. It cannot fetch anything; it sees only what
   step 2 fetched from allowed hosts.
4. **Verification step (deterministic).** Every `figures[].value` must appear verbatim (after
   whitespace normalization) in the fetched text of its own source page, or the item is dropped.
   Every URL host must be allowed. Run the banned-phrase and named-entity scans (§6). Validate
   against the schema (§5) with the same rules the app enforces (`DailyBrief.validate`). A document
   that fails is not published; the previous day's `latest.json` stays, and the job alerts
   (Telegram bridge, `@DudDevBot`).
5. **Publish step.** Write `briefs/<YYYY-MM-DD>.json` and copy it to `latest.json`; publish to the
   `dudleyapps.com` static host at `/econbyte/brief/latest.json` and `/econbyte/brief/<date>.json`
   (Cloudflare Pages via the dudley-web `gh-pages` branch deploy, or an R2 bucket behind the same
   path — the Owner decides; the app cares only about the URL). Set `Cache-Control: max-age=900`.
   Keep 90 days of history on the server; the app keeps the newest 30 on device.

## 5. Output schema (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "briefDate": "2026-09-14",
  "publishedAt": "2026-09-14T21:35:00Z",
  "isSample": false,
  "headline": "one sentence, ≤ 110 characters, states a fact from today's releases",
  "sections": [
    {"type": "released", "title": "What was released", "items": [
      {"title": "Consumer Price Index, August 2026", "releaseDate": "2026-09-11",
       "summary": "2–4 sentences", "meaning": "1–3 sentences",
       "figures": [{"label": "All items, 12 months", "value": "+3.4%"}],
       "source": {"organization": "U.S. Bureau of Labor Statistics", "documentTitle": "…",
                  "url": "https://www.bls.gov/news.release/cpi.nr0.htm", "retrievedAt": "2026-09-14T21:31:12Z"}}
    ]},
    {"type": "scheduled", "title": "Scheduled this week", "items": [
      {"date": "2026-09-16", "title": "…", "organization": "…", "url": "https://…"}
    ]},
    {"type": "concept", "title": "One concept to know", "conceptTitle": "…", "text": "…",
     "linkedCardID": "inf-001"}
  ],
  "disclaimer": "Informational only — not investment advice. …",
  "methodology": "… primary sources only …"
}
```

Rules the app enforces on receipt (`EconByte/Content/DailyBrief.swift`): `schemaVersion == 1`; all
three section types present; every released item has ≥ 1 figure and a complete `source` on an
allowed host over https; every scheduled item has a date, organization and allowed URL; the
concept links a card or lesson; the disclaimer contains "advice"; the methodology contains
"primary". A document failing any rule is discarded and the previous brief stays on screen.

On days with **no releases** (e.g. a Monday with only a schedule), `released` carries one item
built from the most recent release of the prior business day, clearly dated, so the section is
never empty and never invented.

## 6. Editorial guardrails (enforced by scan before publish)

- Banned advice phrases: `should buy`, `should sell`, `invest in`, `buy now`, `sell now`,
  `we recommend`, `best investment`, `will outperform`, `beat the market`, `price target`, `get rich`,
  `guaranteed return`, `risk-free return`, `financial advice`, `investment advice`, `act fast`, `sure thing`.
- Banned prediction phrases: `will rise`, `will fall`, `we expect`, `likely to rise`, `likely to fall`,
  `poised to`, `is set to`, `our forecast`, `we predict`, `will rally`, `will crash`, `will recover`.
  ("Summary of Economic Projections" as a proper noun is allowed.)
- Banned stale words: `today`, `currently`, `recently`, `this year`, `last year`, `right now` — state
  the date or period instead.
- No named companies, funds, brokerages, trademarked indexes, or cryptocurrencies.
- Every number in prose must also appear in `figures` with its source; no arithmetic the release
  did not do, except simple restatements of the same figure ("$100 → about $103.40").
- Attribution sentence in `methodology` every day; `retrievedAt` on every source.

## 7. Operations

- Environment: `ANTHROPIC_API_KEY` (job-scoped key), `BRIEF_PUBLISH_TARGET` (Pages repo token or R2
  credentials), `TELEGRAM_ALERT_CHAT`. Secrets in Railway variables only; never in the repo.
- Logging: per run, the list of URLs fetched with status codes and byte counts, the validator
  result, and the publish result. No user data exists in this system at all.
- Failure policy: any error ⇒ do not publish, alert once, leave `latest.json` untouched. The app is
  built to treat a stale or missing `latest.json` as "no news", never as an error to the reader.
- Cost: one model call per business day over ~20–40 KB of release text; negligible.
- Review-readiness: keep `docs/daily-brief/SERVER.md` and the in-app "How this brief is made"
  screen in agreement — App Review may read either.

## 8. Not in scope for this spec

Notifications for a new brief (a future opt-in, would reuse `NotificationCoordinator`), non-U.S.
editions, a web version, and any use of the brief in marketing (Owner decision; the brief is a
subscriber feature).
