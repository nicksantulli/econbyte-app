# EconByte 1.1.5 integration fact read (Phase 23, 2026-09-15)

An independent read, done while merging Phase 19 (story lessons), Phase 20 (card graphics) and Phase 22 (icon) into
`claude/econbyte-115`. It covers:

- the trimmed quiz checks Phase 19 flagged for a second reader (bry-07, bry-08, bry-09, rpc-06, rpc-08, rpc-09);
- Phase 20's 3 card text fixes (gdp-005, tt-003, cmp-008) and its open item ir-004;
- the British spellings Phase 20 listed (orchestrator order: US English where the meaning stays exact, proper names untouched).

Every item was read against the 1.1.4 wording (`git show main:EconByte/Resources/...`) and, where a fact is at stake,
against the primary source. All edits were made with Python on the raw JSON (exact-match replacement, asserted to occur
once, then re-parsed).

## Changes

| # | Item | Before | After | Why |
|---|---|---|---|---|
| 1 | rpc-06, 2nd check, choice B (the correct answer) | "Maybe a chance fit among many tested rules, before costs" | "Maybe a chance fit among many rules, ignoring trading costs" | "before costs" was ambiguous (before what?). 1.1.4 said the rule "has not yet paid trading costs". The new wording says the record leaves costs out, and stays inside the 35-word screen limit. |
| 2 | bry-08 check, explanation | "... That spread is expected inflation plus an inflation risk premium minus a TIPS liquidity premium, and negative real yields are allowed." | "... Fed research splits that spread into expected inflation, an inflation risk premium and a TIPS liquidity premium, and TIPS auctions allow negative real yields." | (a) The trim stated a model decomposition as plain fact. 1.1.4 attributed it to Federal Reserve Board research, and the lesson's own source (FEDS Notes, "Tips from TIPS", 2019) presents it as a model-based decomposition (D'Amico, Kim and Wei), so the attribution is restored. (b) "negative real yields are allowed" did not say allowed by what. TreasuryDirect's TIPS page: "Treasury TIPS auction rules allow for negative real yield bids." 33 words, under the limit of 35. |
| 3 | ir-004, example (card) | "... and the full effect of one decision can take 4 to 6 quarters to arrive." | "... and the full effect of 1 decision takes quarters, not weeks, to arrive." | "4 to 6 quarters" is not on the cited Federal Reserve page (re-read 2026-09-15: the page gives no timeframe, only effects "over time"), and a range of 1 to 1.5 years for the *full* effect is narrower than the Fed's usual "long and variable lags". An unsourced figure on a card marked verified is misleading, so it was removed. The new wording restates the card's own definition ("a lag usually measured in quarters rather than weeks"). "1 decision" keeps a digit, because the content validator requires a concrete particular in every example. The graphic (conceptual flow) is unchanged. |
| 4 | gdp-005, example (Phase 20 fix, refined) | "... across measures such as payroll employment and real income ..." | "... across measures such as nonfarm payroll employment and real personal income less transfers ..." | Phase 20's correction is right, but "real income" is looser than NBER's measure. NBER: "the two measures we have put the most weight on are real personal income less transfers and nonfarm payroll employment." |
| 5 | sd-007, example | "In a labour market" | "In a labor market" | US spelling |
| 6 | sd-008, example | "Petrol and large cars are complements" | "Gasoline and large cars are complements" | US term; same meaning (the sentence goes on "when fuel costs jump") |
| 7 | tt-005, example | "The organisation was new" | "The organization was new" | US spelling (it refers to the WTO, not a proper name) |
| 8 | tax-003, example | "never appears on the payslip at all" | "never appears on the pay stub at all" | US term |
| 9 | tax-007, example | "writes the cheque to customs" | "writes the check to customs" | US spelling |
| 10 | tax-008, example | "paid as a cheque" | "paid as a check" | US spelling |
| 11 | fp-002, example | "Social Security cheques" | "Social Security checks" | US spelling |
| 12 | emg-010 (pack), definition | "rather than cancelling them" | "rather than canceling them" | US spelling (found by the same scan) |
| 13 | tax-003, example | "totalling 7.65 percent" | "totaling 7.65 percent" | US spelling (found by a follow-up scan of the double-l forms) |
| 14 | rec-002, definition | "have signalled downturns" | "have signaled downturns" | US spelling (same scan) |

**Left alone on purpose:**
- Proper names and titles: "Organisation for Economic Co-operation and Development" (the OECD's official name, 7 source fields) and the Bundesbank document title "Inflation - Lessons Learnt from History".
- "queue(s)": standard US English.
- "flat" and "equally": the same words in US English.

## Verified, no change needed

| Item | Check | Result |
|---|---|---|
| bry-07 check | 7.2 − 4.0 = 3.2 points (BB), 5.1 − 4.0 = 1.1 (A); BB is below BBB−, so non-investment grade. Each trimmed distractor is still plainly wrong by the lesson's definitions; the answer index is unchanged. | Correct |
| bry-09 check | TreasuryDirect, "How Auctions Work": "Treasury first accepts all the non-competitive bids ... All successful bidders get the same rate, yield, or discount margin as the highest accepted bid." A 4.22 bid is below the 4.26 high yield, so it is filled in full. The check matches the lesson's own $30 billion auction chart (high yield 4.26). | Correct |
| rpc-06, 1st check (added in 1.1.5) | Answered by the two beats before it (coin-flip random walks, no memory). | Correct |
| rpc-08 check | Slope (54 − 50) / 4 = 1 per day, so the line is at 50 + 9 = 59 on day 10. The 58.4 low is below it and the 59.3 close above it, so only the intraday rule marks a break. | Correct |
| rpc-09 check | The question no longer repeats the numbers, but the beat right before it gives them all (1,000 days; 116 of 200 signal days; 472 of the other 800). 116/200 = 58%, 472/800 = 59%. | Correct |
| tt-003 (Phase 20 fix) | FRED BOPGSTB CSV, retrieved 2026-09-15: 414 monthly observations from January 1992 through June 2026, all negative (least negative −$831 million, February 1992). A July 2026 observation (−$88,576 million) now exists, so 1.1.4's "all 414 months it covers" had become stale; the new dated wording is exact. | Correct |
| cmp-008 (Phase 20 fix) | FDIC "National Rates and Rate Caps", as of August 17, 2026: savings 0.38, money market 0.63, 12-month CD 1.71. 1 − 1.0038/1.03 = 2.54%, so "about 2.5 percent". The CD: 1 − 1.0171/1.03 = 1.25%, so "about 1.3 percent" still holds. | Correct |
| gdp-005 (Phase 20 fix) | NBER Business Cycle Dating page: peak February 2020, trough April 2020; the recession criteria are "depth, diffusion, and duration". 1.1.4's "far too short to produce two consecutive negative quarters" was false: real GDP fell in both 2020 Q1 and Q2. | Correct (refined, row 4) |

## Gates after the edits

- `node scripts/validate_content.mjs courses EconByte/Resources/courses-v1.json`: 0 errors, 0 warnings. Stats: 27 lessons, 653 beats, 32 checks, max 35 words.
- `node scripts/validate_content.mjs curriculum EconByte/Resources/curriculum-v1.1.json`: 0 errors, 2 warnings. Both warnings are the duplicate-title notices that predate this work (inf-002/usa-004 and lm-001/usa-003).
- `node scripts/validate_content.mjs packs EconByte/Resources/packs-v1.json`: 0 errors, 2 warnings (the same pre-existing duplicate-title pair).
- `node scripts/card_graphics.mjs check --require-all`: 468 graphics, 0 errors, 1 warning (the known illustrative ir-003).
- `scripts/story_fact_diff.py` (1.1.4 lessons against the 1.1.5 beats, all 3 courses): only the known false positive ("The Federal Open Market Committee" in bry-06).
