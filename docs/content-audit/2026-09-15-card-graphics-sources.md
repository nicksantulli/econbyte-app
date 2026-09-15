# EconByte 1.1.5 — card graphics: sources and fact-check record

Date: 2026-09-15 · Branch `claude/econbyte-115-card-graphics` · Contract: `docs/content/CARD-GRAPHICS-1.1.5.md`

All 468 cards now carry a graphic:

| | Cards |
|---|---|
| Core (`curriculum-v1.1.json`) | 180 |
| Packs (`packs-v1.json`) | 288 |

## How every number is backed

| Basis | Graphics | What backs the numbers |
|---|---|---|
| `fromCard` | 283 | Every number appears in the card's own title, definition or example, which the card's existing source already backs (audited 2026-08-30 and 2026-09-14). Anything else is a `derived` value, computed from card numbers by an arithmetic expression the checker re-evaluates. |
| `conceptual` | 148 | No digits anywhere in the graphic. |
| `sourced` | 25 | Real data resolved by a recipe from FRED or the World Bank (table below), retrieved 2026-09-15. |
| `computed` | 7 | Formula series (compound, simple, purchasing power, amortization) computed from card inputs and recomputed by the checker: rr-003, rr-004, cr-004, cmp-001, cmp-003, cmp-007, cmp-009. |
| `illustrative` | 5 | Shapes only. The footnote reads "Illustrative, not real data": ir-001, ir-003, hm-008, rec-008, rr-002. |

The app prints the basis under every graphic except conceptual ones. A sourced graphic's footnote names the organization and the period.

## Sourced graphics (card id → source)

All FRED series are U.S. government or Freddie Mac data, redistributed by the Federal Reserve Bank of St. Louis. Both World Bank series come from World Development Indicators. Nothing is S&P, ICE, Moody's, University of Michigan or NAR data.

In every row, the check column records how the resolved values compare with the card's own figures for the same period.

| Card | Series | Recipe | Check against the card |
|---|---|---|---|
| inf-001 | FRED CPIAUCSL (BLS) | 12-month % change, monthly, 2019–2023 | Jun 2022 = 9.0 ("roughly 9 percent") |
| lm-002 | FRED CIVPART (BLS) | level, monthly, Jan 2016–Apr 2020 | Feb 2020 63.3, Apr 2020 60.1 (exact) |
| lm-011 | FRED LNS12300060 (BLS) | April of each year, 2000–2025 | 2000 81.9, 2020 69.6 (exact); card's Aug 2026 80.4 drawn as a reference line |
| lm-012 | FRED NROU (CBO) | third-quarter values, 1978–2026 | 1978 6.2, 2026 Q3 4.4 (card: "about"); 2026 is a CBO projection, as the card says |
| tt-003 | FRED BOPGSTB, BOPGTB, BOPSTB (Census/BEA) | annual mean of monthly values, 1992–2025 | goods and total negative every year, services positive |
| hm-002 | FRED MORTGAGE30US (Freddie Mac) | first weekly reading each January, 2015–2025 | Jan 7, 2021 = 2.65 (exact) |
| hm-004 | FRED HOUST (Census) | monthly, 2005–2009 | Jan 2006 2,273K (~2.27M); Apr 2009 478K (exact) |
| hm-009 | FRED RHORUSQ156N (Census) | Q2 of each year, 1970–2026 | 2004 69.2, 2016 62.9, 2026 65.0 (exact) |
| hm-012 | FRED A011RE1Q156NBEA (BEA) | Q3 of each year, 1990–2025 | 2005 6.7, 2010 2.4 (exact) |
| rec-006 | FRED UNRATE (BLS) | monthly, 2008–2010 | Jun 2009 9.5, Oct 2009 10.0 (exact) |
| dd-002 | FRED GFDEGDQ188S (OMB/FRB St. Louis) | last quarter of each year; 2026 = Q1 | 2007 63, Q1 2026 123 ("about") |
| dd-011 | FRED MTSDS133FMS (Treasury Fiscal Service) | April of each year, 2015–2026 | $258.4B (2025), $215.0B (2026); deficits only 2020–21 |
| cs-002 | FRED PSAVERT (BEA) | monthly, 2019–2023 | Apr 2020 31.8 (exact) |
| cs-003 | FRED RSAFS (Census) | monthly, 2019–2021 | Mar 2020 $468B, Apr 2020 $401B, −14.4% |
| ei-002 | FRED RSAFSNA and RSAFS (Census) | monthly levels, 2023–2024 | December jump and January drop in the unadjusted series only |
| dep-009 | FRED GDPCA (BEA) | annual, 1929–1938 | 1929 1,191; 1933 877; first above 1929 in 1936 (exact) |
| stg-006 | FRED PCEPI (BEA) | 12-month % change, monthly, 1979–1983 | Jan 1979 7.7, Mar 1980 11.6 peak (exact) |
| gfc-003 | FRED UNRATE (BLS) | monthly, Dec 2007–Oct 2009 | 5.0 and 10.0 (exact) |
| gfc-012 | FRED DRSFRMACBS (Federal Reserve Board) | quarterly, Q1 2007–Q1 2010 | 2.08 and 11.48 (exact); see open item 3 |
| usa-001 | FRED GDP (BEA) | quarterly SAAR, 2016–2026 Q2 | Q2 2026 $32,486B (exact) |
| usa-003 | FRED UNRATE (BLS) | monthly, Jan 2022–Aug 2026 | Aug 2026 4.1 (exact); Oct 2025 was never collected (lapse), so the line has no point there |
| usa-004 | FRED CPIAUCNS (BLS) | 12-month % change, NSA, Jan 2022–Aug 2026 | Aug 2026 3.4 (exact, not seasonally adjusted as the card says); no Oct 2025 point |
| usa-008 | FRED GFDEGDQ188S | quarterly, 2016–2026 Q1 | Q1 2026 122.59 (exact) |
| chn-002 | World Bank NY.GDP.MKTP.KD.ZG (CHN) | annual, 1979–2025 | 2025 5.0 (exact); no average drawn |
| emg-002 | World Bank SI.POV.DDAY (WLD) | annual, 1990–2024 | shares are consistent with the card's counts; no share is stated on the card |

To reproduce these, run `node scripts/card_graphics.mjs check --net`. It re-downloads each series, re-applies the recipe, and fails if any plotted point differs.

## Machine fact-check

`node scripts/card_graphics.mjs check --require-all` finds 468 graphics, 0 errors and 1 warning. The warning is ir-003's worked line ("3% nominal − 5% inflation = −2% real"), which is labelled illustrative and uses no figure from the card.

The checker covers:

- **Structure:** payload matches kind, item counts, label lengths, unit-space coordinates, strictly increasing x, ascending timeline dates, and segment sums no larger than the total.
- **Numbers against basis:** every number shown in a `fromCard`, `computed` or `sourced` graphic must appear in the card prose, in a `derived` value, or in the plotted data. A `conceptual` graphic may show no digits at all.
- **Arithmetic:** every `derived` expression is re-evaluated, and every literal in it must appear in the card or be a unit constant.
- **Formula series:** recomputed exactly.
- **Recipe series:** re-resolved from the cached downloads.
- **House rules:** no stale wording, no advice phrases, no brand or index names, no year after 2026, and no British spellings in graphic text.

`EconByteTests/CardGraphicsTests.swift` repeats the structural, number, arithmetic and house-rule checks at build time. It also confirms that every SF Symbol exists and that every graphic renders.

## Human review

Eleven drafting agents each did a card-by-card adversarial pass over their own group. The phase lead then read all 468 card/graphic pairs side by side and changed 7 graphics:

- **sd-007:** the columns were mislabelled. They are now "Pay above floor" and "Pay below floor".
- **rec-010:** the expression was missing "sum of".
- **dep-012:** the columns "Into the slump" and "Out of it" implied causation the card does not assert. They are now "As it began" and "As it ended".
- **ei-006:** "No, covers everyone" became "None from sampling". Administrative data still has other errors.
- **fdv-010:** the price showed as $22.5. It now shows two decimals.
- **dd-011, chn-005:** removed arithmetic workarounds, and reworded chn-005's note so it names no year the card does not state.

The review also found a renderer bug. Axis labels were compacted to "K/M/B", which would have misstated series already quoted in millions. Axis labels now print the full grouped number.

## Card text fixes (verified factual errors only)

| Card | Was | Now | Evidence |
|---|---|---|---|
| gdp-005 | "…to an April 2020 trough - far too short to produce two consecutive negative quarters, yet unmistakably a recession by every other measure." | "…to an April 2020 trough. It made that call by weighing how deep, how widespread, and how long the decline was across measures such as payroll employment and real income, not by applying a two-quarter GDP rule." | FRED A191RL1Q225SBEA: real GDP −5.2% (2020 Q1) and −28.0% (2020 Q2), so two consecutive negative quarters did occur. The NBER dating page (the card's source) defines a recession by depth, diffusion and duration, and lists payroll employment and real personal income among its measures. Legacy concept pin ("two consecutive quarters") still satisfied. |
| tt-003 | "FRED's monthly balance has been negative in all 414 months it covers, back to January 1992." | "FRED's monthly balance was negative in every month from January 1992 through June 2026." | FRED BOPGSTB includes July 2026 (−88,576), so the series covered 415 months by the 2026-09-14 verification date. The new wording matches the card's own claim period (through June 2026) and cannot go stale. |
| cmp-008 | "…loses about 2.6 percent of its purchasing power in a year" | "…loses about 2.5 percent…" | 1 − 1.0038/1.03 = 2.54%. The 2.6 was the subtraction shortcut, which the sibling card cmp-010 teaches exaggerates a real loss. The certificate's "about 1.3 percent" (exact 1.25%) is unchanged. |

## Open items for the Owner (not changed)

1. **ir-004: "4 to 6 quarters" is unsourced.** *Resolved in the 1.1.5 integration: the number was removed; see `2026-09-15-integration-fact-read.md`.* The cited Federal Reserve page gives no timeframe (checked 2026-09-15); it says only that effects arrive "over time". This is not proven wrong, so the text is unchanged. The graphic uses the definition's "quarters rather than weeks". Re-source it or remove the number.
2. **British spellings in card text.** *Resolved in the 1.1.5 integration (US spellings); see `2026-09-15-integration-fact-read.md`.*
   - "labour" (sd-007)
   - "Petrol" (sd-008)
   - "organisation" (tt-005)
   - "cheque/cheques" (tax-007, tax-008, fp-002)
   - "payslip" (tax-003)

   These breach the US-spelling house rule. They are not factual errors, so they are left for a copy pass. `validate_content.mjs` does not catch them.
3. **gfc-012 series name.** The FRED series is titled "Single-Family Residential Mortgages … All Commercial Banks"; the card says "residential real estate loans … insured U.S.-chartered commercial banks". Both card figures (2.08 and 11.48) match the series exactly. The fallback is fromCard bars.
4. **gdp-006 "Frankfurt".** It is loose shorthand for the euro-area headline: the ECB is in Frankfurt, but Eurostat publishes the GDP figure. The text is unchanged.
5. **OECD figures.** oecd.org returns 403 to this Mac, so these could not be re-opened: mix-009, mix-011, mix-012, wlf-009, wlf-011, wlf-012. Their graphics restate only the card's numbers.
6. **cs-006 wording.** The New York Fed report's "share of borrowers newly falling 30 days behind" may be reported by balances rather than borrowers (the page needs JavaScript). The graphic avoids the distinction.
