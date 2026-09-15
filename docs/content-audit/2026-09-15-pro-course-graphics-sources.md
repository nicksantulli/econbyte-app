# EconByte 1.1.5 (Phase 24): Pro course graphics, sources and fact-check record

Contract: `docs/content/LESSON-GRAPHICS-1.1.5.md`. Catalog: `EconByte/Resources/courses-v1.json`.
Checker: `node scripts/lesson_graphics.mjs check` (0 errors, 22 warnings, all explained below) and
`node scripts/validate_content.mjs courses EconByte/Resources/courses-v1.json` (0 errors, 0 warnings).
All sourced data was retrieved 2026-09-15.

## Coverage

| | Before (1.1.5 build 20) | After (Phase 24) |
|---|---|---|
| Teaching beats (idea and term) | 594 | 594 |
| With a purposeful picture (not none or a symbol) | 293 (49.3%) | 554 (93.3%) |
| Decorative symbols | 126 | 20 |
| No picture | 175 | 20 |
| Typed lesson graphics | 0 | 302 |
| Lessons with one centerpiece | 0 | 27 |

**Graphics by kind:**

| flow | compare | diagram | candles | formula | bars | line | proportion | timeline |
|---|---|---|---|---|---|---|---|---|
| 81 | 74 | 70 | 22 | 22 | 13 | 9 | 9 | 2 |

**Graphics by basis:**

| conceptual | fromLesson | illustrative | computed | sourced |
|---|---|---|---|---|
| 227 | 43 | 24 | 3 | 5 |

## Method

1. **Drafting.** Three writer agents each drafted one course as a fragment (the IDs of beats they changed, plus a
   note per graphic). They worked only through the checker and never edited the catalog.
2. **Machine checks.** Every graphic passes `validateSpec`:
   - structure and limits;
   - house rules;
   - number backing against the lesson's own prose;
   - exact recomputation of `compute` series;
   - re-resolution of FRED recipes;
   - geometric pattern checks on candles (`candleProblems`).

   The Swift mirror (`CardGraphicSpec.validationProblems`, `CandlesGraphic.patternProblems`) runs in
   `StoryLessonsTests` and `CardGraphicsTests`.
3. **Writer adversarial review.** Each writer re-read every graphic against its beat; the review files record
   what changed. Notable fixes:
   - rpc-02/10: a tied swing low was raised;
   - rpc-06/13: "exceed costs to break even" became "cover costs";
   - rpc-06/19: the day-trade dots no longer imply a winning trade;
   - ia-06/19: "Not knowable ahead" became "Uncertain";
   - ia-08/20: the "Buys" cell was corrected;
   - bry-01/15: "Bought above/below face" became "Priced above/below face";
   - bry-04/21: an interpretive row was dropped;
   - bry-07/14: the liquidity cells were hedged;
   - bry-07/21: past tense;
   - the T10Y3MM source attribution was corrected.
4. **Lead review.** The phase lead read all 27 lessons beat by beat with every graphic's payload, and
   recomputed by hand:
   - the candle ratios for every named pattern (rpc-04 doji, hammer and engulfing);
   - the rpc-01 weekly-candle aggregate;
   - binomial P(X ≥ 12 | n = 20) = 25.2% (rpc-09/14);
   - the fee-gap share 19,757 / 67,767 = 29.2% (ia-06/17);
   - the rpc-08/12 line rises, 0.3 × 19 = 5.7 and 0.2 × 19 = 3.8;
   - the bry-05/10 real balance, 148.02 / 1.05^10 = 90.87;
   - bid-to-cover 75.0 / 30.0 = 2.50 (bry-09/16).

   The lead also checked the FII10 note in bry-08/18 against the FRED CSV: yearly averages were −0.48 (2012),
   −0.60 (2020) and −0.92 (2021), and 2013 was +0.07.

## Sourced series (FRED)

| Beat | Series | Publisher (per FRED) | Sample | Agreement with the lesson |
|---|---|---|---|---|
| bry-03/4 | T10Y3MM, 10-year minus 3-month | Federal Reserve Bank of St. Louis | yearly average, 1982–2025 | Beat: the curve is normal "most of the time"; the spread is above zero in most years |
| bry-04/15 | T10Y3MM | Federal Reserve Bank of St. Louis | monthly, Jan 2021–Dec 2024 | Beat: the long inversion "from late 2022 through late 2024" (Cleveland Fed); markers Nov 2022 and Nov 2024 |
| bry-06/10 | FEDFUNDS and GS10 | Board of Governors of the Federal Reserve System (H.15) | monthly, Jan 2021–Dec 2025 | Beat: the curve flattens or inverts during tightening; note: funds rate above the 10-year Dec 2022–Dec 2024, checked month by month by the writer |
| bry-08/6 | T10YIEM, 10-year breakeven | Federal Reserve Bank of St. Louis | yearly average, 2003–2025 | Beat: FRED publishes the 10-year breakeven (the beat names this series) |
| bry-08/18 | FII10, 10-year TIPS real yield | Board of Governors of the Federal Reserve System (H.15) | yearly average, 2003–2025 | Beat: real yields can fall below zero; the lead verified the negative years |

- **Spot-checks.** The writer recomputed every sourced point from an independent `fredgraph.csv` download. The
  only differences are half-cent ties, which the recipe rounds half up (for example T10Y3MM 1989 0.105 → 0.11).
- **Lesson charts.** No lesson `chart` changed. They stay synthetic, and the catalog's editorial-policy text now
  says that a few bond-lesson graphics plot public Federal Reserve series via FRED.

## Warnings left (22, all expected)

- **Source:** every warning is `illustrative: numbers not in the card` on a candle drawing.
- **Where:**
  - rpc-01/1, 4, 7, 10, 18;
  - rpc-02/2, 3, 5, 6, 10;
  - rpc-03/1, 2, 9, 10, 14, 15, 19;
  - rpc-04/2, 3, 6;
  - rpc-08/15, 18.
- **Why they are expected:** a textbook pattern drawing needs OHLC prices that the lesson never states. These
  drawings are labelled "Illustrative, not real data" in the app.
- **Levels the lesson names are used:** 96, 100 and 104 in rpc-03; 102.1 in rpc-08/15.

## Text fixes (logged; the merge tool cannot change text)

| Where | Before | After | Why |
|---|---|---|---|
| bry-02 beat 12, term "Zero-coupon bond" | "…its duration equals its full maturity." | "…its duration is close to, and slightly below, its full maturity." | "Equals" is exact only for Macaulay duration. Beat 7 defines duration as the approximate percent price change per one-point yield change (modified duration), which for a zero-coupon bond is maturity ÷ (1 + yield), just under maturity. Raised by the orchestrator and flagged independently by the bry writer. 26 words on screen. |
| bry-02 beat 12, graphic | note "…so duration equals maturity"; "Duration" guide drawn on the payment | note "…so duration sits just below maturity"; guide moved left of the payment | Agrees with the corrected text. |
| ia-08 beat 2, picture | reused `risk-return-ladder` diagram (four steps: cash, government bonds, corporate bonds, stocks) | conceptual graphic "Three main categories, by historical risk" (Cash, Bonds, Stocks; no numbers) | The beat says "three main categories". The order is from the SEC beginners' guide this lesson cites, and matches ia-01's ladder. Raised by the orchestrator, and noted by the ia writer. |
| Catalog `editorialPolicy` (and `scripts/build_story_courses.mjs`) | "…no real market data is shown anywhere." | Says what lesson graphics rest on, including the FRED series; "no security price is ever plotted" | Five sourced graphics now exist. |
| Settings → Sources & editorial policy → Courses | "Charts that illustrate a concept use synthetic data and say so." | "Every lesson picture says what its numbers rest on: …" | Same reason. |

## Observations not changed (low severity)

- **rpc-02 beat 11 (rpc writer).** The lesson chart's lows over days 1–14 rise almost every day, so strict pullback
  swing lows are hard to see before day 16. "Higher highs and higher lows" is fair as a description; a future chart
  revision could add visible pullbacks.
- **Lesson charts mix compounding conventions (bry writer).** `bry-01-price-vs-yield` uses annual coupons, and the
  10-year bar of `bry-02-duration-bars` uses semiannual. The difference is about 0.1 point, and both are labelled
  synthetic.
- **ia-06/18.** The computed SEC-example endpoints (about $208.8K and $180.6K) subtract each fee from the 4%
  return. The graphic does not attribute exact dollars to the SEC, whose lesson text says only "tens of
  thousands".
- **Text-first graphics.** Flow and compare graphics are 155 of the 302. Each restates its beat in structured
  form, and they are the honest picture where a beat names steps or contrasts rather than figures. Drawing kinds
  (diagram, candles, line, bars, proportion, timeline) are 125, and every centerpiece is a drawing or chart.

## Per-beat sources and review notes

★ = the lesson's centerpiece beat (listed here when the centerpiece is a new graphic).

### ia-01 — Risk and Return

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: A return: what comes back, against what was paid | conceptual. Conceptual (no numbers) | conceptual flow: paid -> gives back over a period (two parts) -> return measured against amount paid. Restates beat 1 only; no numbers. |
| 2 | compare: Income: cash paid out while the asset is held | conceptual. Conceptual (no numbers) | conceptual compare: beat 2 names interest on a bond and a dividend on a share, paid while held. Replaces decorative symbol. |
| 3 | diagram: Capital gain or loss: sale price vs price paid | conceptual. Conceptual (no numbers) | conceptual diagram: gain or loss is the price change between purchase and sale (beat 3). Two schematic paths from one purchase price; no numbers. |
| 5 | formula: Return, as a share of the amount paid | conceptual. Conceptual (no numbers) | conceptual formula: term definition of beat 5 (income plus change in price, as a share of amount paid, over a stated period); matches beat 4 flow. No numbers. |
| 7 | diagram: Variability: the return swings period to period | conceptual. Conceptual (no numbers) | conceptual diagram: a zigzag return, the "variability" face of risk (beat 7). Shape only, no values. |
| 8 | diagram: Loss: ending with less than was put in | conceptual. Conceptual (no numbers) | conceptual diagram: value ends below the amount put in, a negative return (beat 8). Replaces decorative arrow symbol. |
| 9 | diagram: Both faces matter: swings vs outright failure | conceptual. Conceptual (no numbers) | conceptual diagram of beat 9: a highly variable path that never ends a stretch below its start, and a steady path that then fails completely. Schematic, no values. |
| 15 | compare: Same expected payoff, wider swings: no buyers | conceptual. Conceptual (no numbers) | conceptual compare of beat 15: nobody accepts wide swings and a real chance of loss for the same expected payoff; sets up beat 16 (price must fall). Replaces scale symbol. |
| 18 | diagram: More risk widens the range of outcomes | conceptual. Conceptual (no numbers) | conceptual diagram of beat 18: the riskier outcome spread is wider, including worse bad outcomes; its center sits a little higher, consistent with the ladder (higher expected return). Note repeats the beat caveat. |
| 20 | compare: A longer horizon leaves more room to wait | conceptual. Conceptual (no numbers) | conceptual compare of the time-horizon definition (beat 20): months vs years or decades; a longer horizon gives more room to wait out swings. No promise of recovery drawn. Replaces hourglass symbol. |

### ia-02 — Diversification

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | compare: Concentrated vs spread | conceptual. Conceptual (no numbers) | conceptual compare of beat 1 (spreading money across many different holdings instead of concentrating it in one). Replaces symbol. |
| 2 | flow: Idiosyncratic risk belongs to one company | conceptual. Conceptual (no numbers) | conceptual flow restating the term definition (beat 2): examples from the beat, risk belongs to one company or asset alone. |
| 3 | flow: Market risk is shared by nearly all assets | conceptual. Conceptual (no numbers) | conceptual flow restating the term definition (beat 3), parallel to beat 2. |
| 8 | diagram: Company-specific shocks are largely independent | conceptual. Conceptual (no numbers) | conceptual diagram of beat 8: two firms whose yearly returns do not move together (a bad year for one says little about the other). Schematic, no values. |
| 10 | compare: Correlation: how closely returns move together | conceptual. Conceptual (no numbers) | conceptual compare of the correlation term (beat 10): the lower it is, the more swings cancel when combined. |
| 11 | bars: SEC's guide: companies in a stock portion | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov) | fromLesson bars: beat 11 states "only four or five companies is not diversified" and "at least a dozen carefully chosen companies" (dozen = 12). Bar for four or five drawn at 5 and labelled "4 or 5". Attributed to the SEC guide as the beat does; beat 20 disclaimer stands. |
| 15 ★ | diagram: More holdings dilute specific risk, not market risk | conceptual. Conceptual (no numbers) | CENTERPIECE, conceptual diagram of the lesson key idea: adding holdings dilutes company-specific risk (beats 9-10), but the curve flattens at a market-risk floor that more holdings cannot remove (beat 15: 500 instead of 5 helps little). Axis labels carry no numbers. |
| 16 | flow: A shared shock reaches even a spread basket | conceptual. Conceptual (no numbers) | conceptual flow of beat 16 (shared rather than specific shock; a well-spread basket still has losing years); "most companies together" echoes the check explanation. Replaces symbol. |
| 17 | diagram: Categories that do not move together soften swings | conceptual. Conceptual (no numbers) | conceptual diagram of beat 17: shares and bonds that have not moved together; the mix line is the point-by-point average of the two schematic lines, so it swings less. Replaces pie symbol. Not an allocation. |

### ia-03 — Index Funds vs Active Management

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: A market index: a list plus a weighting rule | conceptual. Conceptual (no numbers) | conceptual flow of beats 1-2: a list of securities, a weighting rule, a combined value. Replaces list symbol. |
| 2 | diagram: An index's value tracks its list as a whole | conceptual. Conceptual (no numbers) | conceptual diagram of the market-index term (beat 2): three thin member lines and a bold index line drawn as their simple average at each point (equal weights, schematic only). |
| 3 | compare: An index vs an index fund | conceptual. Conceptual (no numbers) | conceptual compare of beat 3 (nobody can buy an index directly; an index fund is a pooled fund that tries to match one) plus the index term (beat 2). |
| 5 | formula: An index fund's aim, in one line | conceptual. Conceptual (no numbers) | conceptual formula of the index-fund term (beat 5): aims to match the index return before fees; "≈" because beat 16 adds trading costs and imperfect tracking. |
| 6 | flow: Active management: a manager makes the choices | conceptual. Conceptual (no numbers) | conceptual flow of beat 6 (manager chooses holdings and when to trade, pursuing a stated goal, often to do better than a benchmark). |
| 8 | diagram: An active fund tries to outpace a benchmark | conceptual. Conceptual (no numbers) | conceptual diagram of the active-management term (beat 8): a fund weaving above and below its benchmark; ends almost level so it implies neither success nor failure (beat 9: depends on skill). |
| 9 | flow: The SEC's trade-off for active funds | conceptual. Conceptual (no numbers) | conceptual flow restating beat 9's three clauses: potential to do better, result depends on skill, extra activity usually means higher fees and trading costs. Replaces symbol. |
| 10 | compare: What passive management usually means | conceptual. Conceptual (no numbers) | conceptual compare of beat 10 (passive usually means less trading, lower fees, fewer taxable gains). The Active column is the comparison beat 10's comparatives imply; beat 9 separately states active's higher fees and trading costs. |
| 11 | flow: Same holdings, different fees | conceptual. Conceptual (no numbers) | conceptual flow of beat 11; replaces the chart here to break a 4-beat run (beats 11-14) since beat 11 states no figures; the chart is still shown on beats 12-14. "Same return before costs" is the check explanation (beat 14). |
| 15 | diagram: Not every index fund costs less than every active fund | conceptual. Conceptual (no numbers) | conceptual diagram of beat 15 (the SEC cautions not every index fund is cheaper than every active fund): two fee ranges that overlap; index range sits lower, consistent with beat 10 'usually lower fees'. No values. |
| 16 | diagram: Tracking error: the gap between fund and index | conceptual. Conceptual (no numbers) | conceptual diagram of the tracking-error term (beat 16): an index fund trailing its index; gap exaggerated for legibility. |
| 17 | formula: All owners together earn the market return | conceptual. Conceptual (no numbers) | conceptual formula of beat 17: across all owners together, the return before costs is the market return. |
| 18 | flow: The arithmetic, before costs | conceptual. Conceptual (no numbers) | conceptual flow of beats 17-18: all owners earn the market return before costs; whole-market index funds earn roughly that; so the remaining owners, active managers as a group, must too. |
| 21 | diagram: Some managers outpace; the arithmetic is the average | conceptual. Conceptual (no numbers) | conceptual diagram of beat 21 with beat 20: a spread of active results after costs centered a little below the benchmark (beat 20: after costs active trails), with a tail above it (beat 21: individuals can and do outpace in a given period). Bell shape is schematic, not data. |

### ia-04 — Value, Growth and Dividends

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 2 | flow: Value: a low price relative to earnings or assets | conceptual. Conceptual (no numbers) | conceptual flow of beat 2 (value label: low price relative to earnings or assets; buyer thinks price understates worth). |
| 3 | flow: Growth: a high price relative to earnings | conceptual. Conceptual (no numbers) | conceptual flow of beat 3 (high price relative to earnings because buyers anticipate earnings expand quickly). |
| 4 | compare: Both labels are judgments, and can be wrong | conceptual. Conceptual (no numbers) | conceptual compare of beat 4, restating the two judgments from beats 2-3; both can turn out wrong. Replaces scale symbol. |
| 5 | flow: A dividend: profit paid out to shareholders | conceptual. Conceptual (no numbers) | conceptual flow of beat 5 (a portion of profit paid to shareholders, usually in cash on a regular schedule). Replaces banknote symbol. |
| 7 | diagram: A board can cut or stop a dividend at any time | conceptual. Conceptual (no numbers) | conceptual diagram of beat 7: a dividend paid, then cut, then stopped. Levels are schematic. |
| 9 | formula: Dividend yield | conceptual. Conceptual (no numbers) | conceptual formula of the dividend-yield term in beat 9 (yearly dividends per share divided by share price, as a percentage). The lesson gives no yield figures, so no example. |
| 12 | bars: $50 share price vs $2.50 earnings: a P/E of 20 | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov); derived 20 = 50 / 2.5 | fromLesson bars replacing the stat "20": beat 12 states $50 price, $2.50 earnings per share, P/E 20; derived 50 / 2.5 = 20. The price bar is visibly 20 times the earnings bar, which the stat could not show. |
| 13 | formula: Price-to-earnings ratio | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov); derived 20 = 50 / 2.5 | fromLesson formula of the P/E term (beat 13); worked example $50 / $2.50 = 20 from beat 12 (the beat before). "Past year" = beat 10 "past twelve months". Expression avoids "P/E" slash (checker display rule). |
| 15 | diagram: P/E compares with its own past or other companies | conceptual. Conceptual (no numbers) | conceptual diagram of beat 15: one share's P/E over time (its own past) against another company's level; note repeats the beat caveat. Replaces ruler symbol. |

### ia-05 — Dollar-Cost Averaging, Allocation and Rebalancing

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: The same sum on a schedule, whatever the price | conceptual. Conceptual (no numbers) | conceptual diagram of beat 1: purchases at regular intervals regardless of the price path. Replaces cart symbol. |
| 3 | formula: Average cost vs simple average price | conceptual. Conceptual (no numbers) | conceptual formula of beat 3: average cost per unit is total spent over units bought; the note restates beats 2-3 (more units at low prices pull it below the simple average price). |
| 4 | flow: A set sum from each paycheck | conceptual. Conceptual (no numbers) | conceptual cycle of beat 4 (a set sum from each paycheck into a retirement account). Replaces banknote symbol. |
| 8 | diagram: If the price ends below the $19.91 average cost | illustrative. Illustrative, not real data (labelled in the app) | illustrative diagram of beat 8: a price path that ends below the $19.91 average cost, so the holding is worth less than the $1,200 put in. Both figures are from beat 8; the path shape is invented. Replaces warning symbol. |
| 10 | compare: One purchase date vs purchases spread over time | conceptual. Conceptual (no numbers) | conceptual compare of beat 10 (spreading purchases spreads the risk of buying everything at a high point and removes the temptation to guess when to buy). |
| 11 | diagram: Money held back misses any rise meanwhile | conceptual. Conceptual (no numbers) | conceptual diagram of beat 11: uninvested money stays flat while an invested sum rises; drawn only for the rising case the beat describes. |
| 12 | compare: A large sum: a debated choice | conceptual. Conceptual (no numbers) | conceptual compare of beat 12 using only the two trade-offs beats 10-11 state; symmetric, so it recommends neither. |
| 19 | bars: Shares slice: start, after the run, rebalanced | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov) | fromLesson bars: beat 18 (the beat before) states the 60 percent start and 75 percent after a strong run; beat 19 says rebalancing brings it back to the chosen mix, i.e. 60. The lesson's own example, not a suggested mix. Replaces symbol. |
| 20 | compare: Two ways to decide when to rebalance | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov) | fromLesson compare of beat 20: calendar (say every six or twelve months) or a band a slice must not stray past. Digits 6 and 12 are the beat's "six or twelve". Replaces calendar symbol. |

### ia-06 — Costs and Fees

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: Every pooled fund has running costs | conceptual. Conceptual (no numbers) | conceptual flow listing the running costs beat 1 names. Replaces tray symbol. |
| 2 | flow: The expense ratio passes costs to owners | conceptual. Conceptual (no numbers) | conceptual flow of beat 2 (costs passed to owners through the expense ratio, a percentage of assets taken each year). Replaces percent symbol. |
| 4 | flow: Not billed: it comes out of the fund | conceptual. Conceptual (no numbers) | conceptual flow of beat 4 (not billed separately, comes out of fund value, easy to overlook, standardized fee table in the prospectus). Replaces doc symbol. |
| 5 | formula: Expense ratio | conceptual. Conceptual (no numbers) | conceptual formula of the expense-ratio term (beat 5): share of fund assets deducted each year for operating costs, including management and distribution fees. |
| 7 | compare: Two trading costs | conceptual. Conceptual (no numbers) | conceptual compare of beat 7: a broker's commission, or a dealer's markup when selling from its own stock. |
| 8 | diagram: Bid-ask spread: buy price vs sell price | conceptual. Conceptual (no numbers) | conceptual diagram of beat 8: the spread between the buy price and the slightly lower sell price at the same moment; gap exaggerated for legibility. |
| 9 | flow: Transaction fees: charged per trade | conceptual. Conceptual (no numbers) | conceptual flow of beat 9 (commissions, markups and sales loads are transaction fees charged each time an investment is bought or sold). |
| 14 | flow: Why a 1% fee costs more than 1% | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov) | fromLesson flow of beats 14-15: a fee taken in year one does not just cost that 1 percent; the money removed would have grown every later year. 1 = beat 14 "1 percent" / "year one". |
| 17 | proportion: A 0.9-point gap takes roughly 29% of the ending value | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov); derived 19757 = 67767 - 48010, 29.15 = (67767 - 48010) / 67767 * 100 | fromLesson proportion replacing the stat "29%": whole bar = the low-fee ending value $67,767 (beat 16, the beat before); segment = high-fee ending value $48,010; remainder (printed by the app as 19,757) = derived 67,767 - 48,010; 19,757 / 67,767 = 29.15%, "roughly 29 percent" (beat 17). 0.9 and 29 in the title are stated on beat 17. |
| 18 | line: $100,000 at 4% for 20 years: 0.25% vs 1.00% fee | computed. Computed: 0.25% yearly fee = {"model":"compound","principal":100000,"ratePct":3.75,"years":20,"step":2}; 1.00% yearly fee = {"model":"compound","principal":100000,"ratePct":3,"years":20,"step":2} (inputs stated in the lesson; lesson sources: U.S. Securities and Exchange Commission, Investor.gov; U.S. Securities and Exchange Commission, Investor.gov; U.S. Securities and Exchange Commission, Investor.gov) | computed line of the SEC example in beat 18: $100,000 for 20 years at derived net rates 4 - 0.25 = 3.75% and 4 - 1.00 = 3%. Endpoints recomputed by hand: 100,000 x 1.0375^20 = 208,815; 100,000 x 1.03^20 = 180,611; gap 28,204, i.e. 'tens of thousands of dollars behind' as the beat says. Title does not claim these are the SEC's own printed figures (net-rate method stated in the note). Replaces building symbol. |
| 19 | compare: Fees are known in advance; returns are not | conceptual. Conceptual (no numbers) | conceptual compare of beat 19 (fees are one of the few facts known in advance; disclosed in the prospectus per beat 4 and the recap). "Returns are not known in advance" is the contrast beat 19 implies and matches beat 22 (every fund carries the risks of what it holds) and ia-01 (risk is uncertainty about return). |

### ia-07 — Behavioral Biases

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | compare: The textbook investor vs real decisions | conceptual. Conceptual (no numbers) | conceptual compare of beat 1 (social, mental and emotional factors pull real decisions away from the calm, self-interested investor of textbook models). Replaces brain symbol. |
| 2 | compare: The departures are not random | conceptual. Conceptual (no numbers) | conceptual compare of beat 2 (departures are not random: investors tend to make the same mistakes again and again). |
| 4 | compare: Mistakes the report lists | conceptual. Conceptual (no numbers) | conceptual compare listing all nine mistakes in beat 4 (too few investments, trading often, following the herd, favoring the familiar, selling winners, holding losers, optimism, short-term thinking, overconfidence). The two column heads group them for legibility; the report itself does not split them. |
| 5 | flow: Overconfidence: a bias of judgment | conceptual. Conceptual (no numbers) | conceptual flow of beat 5 (common among investors, a trigger for a wide range of errors, one place it shows up is trading activity). |
| 6 | formula: What the working paper combined | conceptual. Conceptual (no numbers) | conceptual formula of beat 6: the NBER paper combined stock trades with tax filings, driving records and psychological profiles. No date shown (May 2006 stays in the text). Replaces magnifying-glass symbol. |
| 7 | diagram: More overconfidence, more trading | conceptual. Conceptual (no numbers) | conceptual diagram of beat 7: investors measured as more overconfident traded more often, even after controls; drawn as a simple upward relation (direction only, no slope or data from the paper). |
| 8 | flow: The report's link: trading and results | conceptual. Conceptual (no numbers) | conceptual flow of beat 8 (the report links active trading with overconfidence and concludes active trading generally leaves a portfolio underperforming). |
| 9 | diagram: Loss aversion: avoiding losses weighs more | conceptual. Conceptual (no numbers) | conceptual diagram of beat 9: losses carry more weight than equal-sized gains (steeper line on the loss side). Straight lines on purpose: the lesson states only the asymmetry, so the prospect-theory curvature is not drawn. Replaces scale symbol. |
| 10 | compare: The disposition effect | conceptual. Conceptual (no numbers) | conceptual compare of the disposition-effect term (beat 10): sell gainers too soon, hold losers too long; closely tied to loss aversion. |
| 15 | flow: Momentum, herding and bubbles | conceptual. Conceptual (no numbers) | conceptual flow of beat 15 (researchers tie momentum investing to herd behavior; it can give rise to speculative bubbles). |
| 17 | diagram: Money in after a climb, out after a drop | conceptual. Conceptual (no numbers) | conceptual diagram of beat 17: money goes in after prices have climbed and out after they have dropped. Past-shape only; no signal about what comes next. Replaces uptrend symbol. |

### ia-08 — Rebalancing in Practice

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: Drift: stocks climb faster, their slice grows | conceptual. Conceptual (no numbers) | conceptual diagram of beat 1: stocks climbing faster than bonds, so the stock slice grows without anyone buying more. Replaces pie symbol. |
| 2 | diagram: Three main categories, by historical risk | conceptual. Conceptual (no numbers) | Lead fix (orchestrator note): replaced the reused four-step risk-return ladder (cash, government bonds, corporate bonds, stocks) with a conceptual three-category picture matching the beat's 'three main categories'. Stocks highest per the beat; the cash < bonds < stocks order is the SEC beginners' guide this lesson cites and ia-01's ladder. No numbers. |
| 3 | flow: Rebalancing returns a mix to its original shares | conceptual. Conceptual (no numbers) | conceptual cycle of beat 3 (the guide's definition: bring a portfolio back to its original mix). Replaces circular-arrows symbol. |
| 9 | proportion: A target mix: this lesson's example | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov) | fromLesson donut of the target-mix term (beat 9) using the 60 percent stocks / 40 percent bonds example stated on beats 4 and 21; title and note mark it as the lesson example, not a recommendation (beat 29). No digits in its text, so no agreement warning; the legend prints 60 and 40 from the data. |
| 10 | compare: Two ways to decide when | conceptual. Conceptual (no numbers) | conceptual compare for beat 10 ("Two ways to decide when"): calendar on fixed dates with the calendar as reminder; threshold from beat 12 (investments signal). Replaces calendar symbol. |
| 11 | flow: Calendar rebalancing | conceptual. Conceptual (no numbers) | conceptual cycle of the calendar-rebalancing term (beat 11): reset on fixed dates whatever the size of the drift. |
| 15 | compare: Inside vs outside the tolerance band | conceptual. Conceptual (no numbers) | conceptual compare of the tolerance-band term (beat 15): threshold rebalancing acts only when the share moves outside. Wording avoids the check choices on beat 16. |
| 17 | diagram: A calendar's blind spot: tiny or large drift | conceptual. Conceptual (no numbers) | conceptual diagram of beat 17: reset on each fixed date, once after a tiny drift, once after a large drift that built between dates. |
| 19 | flow: Route one: sell and buy | conceptual. Conceptual (no numbers) | conceptual flow of route one in beat 19 (sell some of an overweighted category, use the money to buy an underweighted one). |
| 20 | compare: Three routes back to the target mix | conceptual. Conceptual (no numbers) | conceptual compare of the three routes in beats 19-20; route three is for someone making regular contributions, directed until the mix is back in balance. Replaces list symbol. |
| 22 | proportion: $78,000 of $119,000 in stocks: about 65.5% | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov); derived 65.5 = 78000 / 119000 * 100 | fromLesson proportion replacing the stat: beat 22 states $78,000 stocks, $41,000 bonds, total $119,000, about 65.5 percent. Recomputed: 60,000 x 1.30 = 78,000; 40,000 x 1.025 = 41,000; 78,000 / 119,000 = 65.55%. |
| 24 | proportion: $11,000 to bonds: $78,000 is 60% of $130,000 | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov); derived 130000 = 78000 / 60 * 100 | fromLesson proportion replacing the stat: beat 24 states $11,000 of new money all to bonds and $78,000 = 60 percent of $130,000; bonds before = $41,000 (beat 22). 78,000 + 41,000 + 11,000 = 130,000; 78,000 / 130,000 = 60%; bonds 52,000 = 40%. |
| 25 | flow: Before rebalancing, check the costs | conceptual. Conceptual (no numbers) | conceptual flow of beat 25 (the guide says to check whether the method will trigger transaction fees or tax consequences). |
| 27 | compare: Rebalancing runs against the trend | conceptual. Conceptual (no numbers) | conceptual compare of beat 27: rebalancing trims what has done well and adds to what lagged, the reverse of trend-following (ia-07 beat 14: buy high recent returns, sell low). Replaces up-down arrows symbol. |

### ia-09 — Share Classes, Loads and Breakpoints

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: One fund, several classes of shares | conceptual. Conceptual (no numbers) | conceptual flow of beat 1 (one fund sells several classes while keeping a single portfolio and adviser). Replaces stack symbol. |
| 2 | compare: Share classes: same portfolio, own fees | conceptual. Conceptual (no numbers) | conceptual compare of the share-class term (beat 2) with beat 1: same portfolio and adviser; each class carries its own fees and expenses. |
| 3 | formula: Different fees, different returns | conceptual. Conceptual (no numbers) | conceptual formula of beat 3: each class carries its own fees, so owners of different classes earn different returns; matches the model in beat 13 (same return before class costs). |
| 4 | diagram: Lowest fees at first may not stay lowest | conceptual. Conceptual (no numbers) | conceptual diagram of beat 4 (the SEC bulletin: the class with the lowest initial fees may not be the lowest over time). Two schematic cumulative-fee paths that cross. Replaces building symbol. |
| 5 | flow: Front-end sales load | conceptual. Conceptual (no numbers) | conceptual flow of the front-end load term (beat 5): a percentage of the purchase price, so part of the money is not invested. |
| 6 | proportion: FINRA's example: $1,000 with a 5% charge | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)); derived 50 = 1000 * 5 / 100 | fromLesson proportion replacing the flow on beat 6: $1,000 purchase, 5 percent charge, $50 up front, $950 in shares (all stated on beat 6). The remainder the app prints (50) = derived 1000 x 5 / 100. Shows the uninvested slice, which the flow could not. |
| 7 | diagram: A deferred sales charge shrinks with time held | conceptual. Conceptual (no numbers) | conceptual diagram of the CDSC term (beat 7): paid only on sale, normally shrinking the longer shares are held until it disappears. No schedule drawn. |
| 8 | flow: The 12b-1 fee: ongoing, from fund assets | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)) | fromLesson flow of the 12b-1 term (beat 8): an ongoing fee paid out of fund assets to cover marketing and selling fund shares. Only digits are the fee name "12b-1", stated on the beat. |
| 10 | flow: Class C: no front-end load | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)) | fromLesson flow of beat 10 (no front-end load, full purchase invested, often about 1 percent if sold within a short time, usually one year). Replaces clock symbol. |
| 11 | diagram: Class C keeps its higher yearly expenses | conceptual. Conceptual (no numbers) | conceptual diagram of beat 11: Class C's higher yearly expenses persist for as long as the shares are held; Class A's lower yearly charge is stated on beat 9. Levels schematic. |
| 12 | compare: No-load classes still have running costs | conceptual. Conceptual (no numbers) | conceptual compare of beat 12 (no-load classes skip sales loads but, like every class, still have ongoing operating costs). |
| 22 | diagram: Breakpoints: a lower load for larger amounts | conceptual. Conceptual (no numbers) | conceptual step diagram of beat 22 (volume discounts on the Class A front-end load, depending on the amount invested); "lower still" matches beat 23 "reduced further". No thresholds drawn. |
| 23 | bars: FINRA's example breakpoint schedule | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)) | fromLesson bars of beat 23: FINRA's example load 5.75 percent under $50,000 and 4.50 percent for $50,000 to $99,999; larger tiers are not given numbers, so they appear only in the note. |
| 24 | bars: Sales charges: $49,000 vs $50,000 purchase | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)); derived 2817.5 = 49000 * 5.75 / 100, 2250 = 50000 * 4.50 / 100 | fromLesson bars replacing the compare: beat 24 states $2,817.50 on $49,000 and $2,250 on $50,000; derived 49,000 x 5.75% = 2,817.50 and 50,000 x 4.50% = 2,250 (rates from beat 23). The bars show the larger purchase paying less. |
| 25 | flow: Letter of intent | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Financial Industry Regulatory Authority (FINRA)) | fromLesson flow of the letter-of-intent term (beat 25): commit to buy a specified amount over a period, usually 13 months, earning the breakpoint discount on each purchase. |
| 26 | formula: Rights of accumulation | conceptual. Conceptual (no numbers) | conceptual formula of beat 26: shares already held, and those of certain related parties such as a spouse or children, count toward the threshold. Replaces person symbol. |

### rpc-01 — Candlestick Anatomy and Timeframes

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | candles: A candlestick chart: one candle per period | illustrative. Illustrative, not real data (labelled in the app) | Illustrative 8-candle chart (prices near 50, deliberately unlike the lesson chart near 100 so it is not read as the same data). All OHLC valid; 5 up and 3 down candles. Replaces decorative symbol. |
| 4 | candles: One candle records four prices | illustrative. Illustrative, not real data (labelled in the app) | Single illustrative up candle with annotate ohlc: open 100, high 103, low 98.5, close 102 (high ≥ close, low ≤ open). Shows the beat's high/low/OHLC idea; replaces a text stat. |
| 7 | candles: An up candle and a down candle | illustrative. Illustrative, not real data (labelled in the app) | Candle 1 closes 102.0 above its 100.0 open (up, blue); candle 2 closes 100.2 below its 102.0 open (down, amber); the renderer legend names the colors, matching the beat's close-vs-open rule. |
| 10 | candles: A long upper wick: price visited but did not stay | illustrative. Illustrative, not real data (labelled in the app) | Candle 3: body 0.5 (100.8→101.3), upper wick 2.3 (to 103.6) vs other candles' wicks ≤0.6, so the level 103.6 was visited and left. Pattern 'none' on purpose: this lesson names no pattern. Chart rpc-01-candles stays on beats 8 and 9 (beat 9 says 'each candle here'). |
| 13 | compare: After-hours trades are kept apart | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 13: after-hours trades are tagged separately and do not change the regular-session close, high or low. Replaces decorative clock symbol. |
| 14 | flow: How a close is chosen | conceptual. Conceptual (no numbers) | Conceptual chain restating the term: the close is the last trade in the period under the data provider's session rules. |
| 15 | compare: Two vendors, two closes for one day | conceptual. Conceptual (no numbers) | Conceptual: beat 15 says two vendors can print different closes if one includes after-hours trades. Vendor names are generic letters, no brands. |
| 16 | compare: Timeframe: the span one candle covers | conceptual. Conceptual (no numbers) | Conceptual: the three example timeframes the term names; for a fixed stretch of history, longer spans give fewer candles (a direct consequence of the definition, no figures). |
| 18 | candles: Five daily candles and the weekly candle they make | illustrative. Illustrative, not real data (labelled in the app) | Aggregate verified exactly: weekly open 100.0 = day 1 open; high 102.3 = max(101.4,101.2,100.8,102.3,102.0) (day 4); low 98.6 = min(99.5,99.0,98.6,100.1,100.4) (day 3); close 100.8 = day 5 close. A choppy week (3 up, 2 down) becomes one small-bodied candle, supporting beat 19. Illustrative prices. |

### rpc-02 — Trends and Ranges

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | compare: Three labels for past price shapes | conceptual. Conceptual (no numbers) | Conceptual summary of the three labels, using the lesson's own definitions (beats 3, 5, 6). Replaces decorative symbol. |
| 2 | candles: A swing high: lower prices on both sides | illustrative. Illustrative, not real data (labelled in the app) | Highs 100.8, 101.5, 102.4, 103.2, 102.8, 102.1, 101.5: candle 4 (103.2) is a local peak with lower highs on both sides, the term's definition. Illustrative. |
| 3 | candles: An uptrend: higher highs and higher lows | illustrative. Illustrative, not real data (labelled in the app) | Swing highs 102.5 (c3), 103.6 (c8), 104.5 (c12) rise; lows rise from 99.6 (c1, first candle) to swing lows 100.6 (c5) and 101.7 (c10). Each swing point verified against both neighbors (e.g. c5 low 100.6 < c4 101.2 and c6 100.8). Illustrative. trend-channel diagram stays on beat 4 and check 7. |
| 5 | candles: A downtrend: lower highs and lower lows | illustrative. Illustrative, not real data (labelled in the app) | Exact mirror of the beat 3 uptrend (price → 204 − price, high↔low): swing highs 104.4, 103.4, 102.3 fall; swing lows 101.5, 100.4, 99.5 fall. OHLC validity preserved by the mirror. Illustrative. |
| 6 | candles: A range: swings stay inside a band | illustrative. Illustrative, not real data (labelled in the app) | Every high ≤ 102.0 and every low ≥ 98.0; swing highs 102.0/101.9 and swing lows 98.0/98.0 at roughly the same levels (the beat's range definition). Illustrative levels, not the lesson chart's 102.6/100.5, which beat 12 shows on the chart itself. |
| 10 | candles: A run of higher highs, then a lower high | illustrative. Illustrative, not real data (labelled in the app) | First 10 candles are the beat 3 uptrend (highs 102.5, 103.6); candle 12 high 103.2 is a swing high (c11 103.0, c13 102.6) below 103.6, and c14 low 100.9 is below the prior swing low 101.7 (c11 low set to 101.8 so c10 is a strict swing low): the run ended, visible only afterward. Describes the past; no forward label. Breaks the 4-in-a-row chart run (beats 9–12). |
| 13 | diagram: Fell, rose for three years, then drifted sideways | conceptual. Conceptual (no numbers) | Conceptual sketch of the example: time axis proportional to 6 + 36 + 2 = 44 months (decline ends at 6/44 = 0.136, sideways from 42/44 = 0.955). No numbers printed. |
| 15 | compare: Same asset, three timeframes, three labels | conceptual. Conceptual (no numbers) | Conceptual: restates beats 14–15 (five-year weekly = uptrend, two-month daily = range, week of hourly might read as downtrend). Beat 15 says 'might', hence the lesson's hedge is carried by the text on the same screen. |
| 16 | flow: Each timeframe keeps different detail | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 16. |
| 18 | compare: Name the timeframe with the trend | conceptual. Conceptual (no numbers) | Conceptual: restates beat 18 (people say which timeframe they mean). No advice framing. |

### rpc-03 — Support and Resistance

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | candles: Support: declines that stopped near 96 | illustrative. Illustrative, not real data (labelled in the app) | Three declines end with lows 96.0 (c3), 96.0 (c8), 96.1 (c12) and turn up; no low is below 96.0. The level 96 is the lesson's own support level (beat 11 / chart caption), so the drawing agrees with the chart. Replaces diagram on the term beat; support-resistance diagram stays on beats 3–4. |
| 2 | candles: Resistance: rallies that stopped near 104 | illustrative. Illustrative, not real data (labelled in the app) | Exact mirror of beat 1 (price → 200 − price): rally highs 104.0, 104.0, 103.9 turn down, none above 104. 104 is the lesson's resistance level. |
| 5 | flow: Why a past turning level gets watched | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 5 ('may be a place where they show up again'); the hedge 'may' is kept, no prediction. |
| 7 | compare: Two kinds of order | conceptual. Conceptual (no numbers) | Conceptual: beat 6 defines a market order (SEC: buy or sell at the going price), beat 7 standing orders at specific prices. Nothing added. |
| 9 | candles: Rallies that stalled at a round number | illustrative. Illustrative, not real data (labelled in the app) | Highs reach exactly 100.0 on c4 and c8 and turn down; 100 is the term's own example of a round number. Illustrative; describes past turns only. |
| 10 | candles: A later rally nearing a previous high | illustrative. Illustrative, not real data (labelled in the app) | Previous high 103.0 on c4; the drawing ends on c9 with high 102.9 just under it, so it shows the remembered level without showing (or implying) what happened next. |
| 14 | candles: Support gave way, so the line was redrawn | illustrative. Illustrative, not real data (labelled in the app) | Lows 98.0 on c4 and c7 held; c8 closes 96.8 below 98 (the break); later lows 94.6 (c10, c13) define the redrawn line. Illustrative; the 'Break' label names a past move only. |
| 15 | candles: A breakout: a close through a level that had held | illustrative. Illustrative, not real data (labelled in the app) | Highs 104.0 (c2, c5) and 103.9 (c7) never exceed 104; c8 closes 105.0 above it. The drawing ends on the breakout candle, so it shows the definition, not the aftermath. Replaces a repeated diagram. |
| 16 | compare: A line organizes the chart; it binds nothing | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 16 (and beat 13's 'summary of past turns'). Replaces decorative warning symbol. |
| 18 | compare: More touches describe the past better | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 18: touches improve the description; nothing says bounce or break. |
| 19 | candles: Same peaks, two reasonable resistance lines | illustrative. Illustrative, not real data (labelled in the app) | Three peaks: wick highs 103.6, 104.1, 103.8; body tops 103.1, 103.4, 103.3. One reader draws at the highest wick (104.1), another through the body tops (103.3): same chart, lines placed differently, as beat 19 says. Illustrative. |

### rpc-04 — Common Candle Patterns and the Evidence

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | compare: Three candle shapes and what they record | conceptual. Conceptual (no numbers) | Conceptual summary using the lesson's definitions (beats 2, 3, 6). Replaces decorative symbol. |
| 2 | candles: A doji: open and close nearly equal | illustrative. Illustrative, not real data (labelled in the app) | Doji c4: open 100.5, close 100.55, body 0.05; range 101.6 − 99.4 = 2.2; body = 2.3% of range (checker ≤10%, lesson 'nearly equal, almost no body'). Wicks 1.05 up / 1.1 down: it ended where it began. |
| 3 | candles: A hammer after a decline | illustrative. Illustrative, not real data (labelled in the app) | Hammer c6: open 99.4, close 99.9, body 0.5; lower wick 99.4 − 97.9 = 1.5 (3.0× body; lesson 'at least about twice'); upper wick 0.05 = 2.4% of the 2.05 range (little or no upper wick); body at the top of the range. Prior decline: five lower closes 103.1→99.6 (checker: c5 close 99.6 < c3 close 101.4). Lesson chart stays on beats 4, 5, 7, 8. |
| 6 | candles: An engulfing pair: the second body covers the first | illustrative. Illustrative, not real data (labelled in the app) | c4 down body 100.6→100.1 (0.5); c5 up body 99.9→101.1 (1.2) opens below 100.1 and closes above 100.6, covering the whole first body (term definition). After a decline: closes 102.2, 101.4, 100.6 (checker c3 100.6 < c1 102.2). Opposite colors (amber then blue). Breaks the six-beat run of the same chart. |
| 9 | flow: A pattern name is shorthand for OHLC | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 9. |
| 11 | flow: Technical analysis in three steps | conceptual. Conceptual (no numbers) | Conceptual chain restating the term definition. Replaces decorative magnifying glass. |
| 14 | timeline: The Lo, Mamaysky and Wang test: data and paper | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research) | fromLesson: 1962–1996 stated on beat 14, March 2000 on beat 13 (the beat before). Chronological. Replaces a stat with the evidence's time frame. |
| 15 | flow: What the test asked and reported | conceptual. Conceptual (no numbers) | Conceptual chain restating beats 14–15 (computer detection; days after a pattern vs ordinary days; several patterns carried some incremental information). No claim about profit. |
| 18 | flow: Information is not profit | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 18. Replaces decorative warning symbol. |
| 21 | compare: Currency trading rules, with and without intervention | conceptual. Conceptual (no numbers) | Conceptual restatement of beats 20–21 (NBER WP 5505): some predictive value, shrinking sharply once central bank intervention periods are set aside. 'Much smaller' renders 'shrank sharply'. |
| 22 | flow: Anomalies after trading costs | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 22 (NBER WP 20721): few high-turnover strategies stayed statistically significant after trading costs. |

### rpc-05 — Moving Averages and Volume

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 4 | formula: A simple moving average | conceptual. Conceptual (no numbers) | Conceptual formula restating the term (arithmetic mean of the last N closes; beat 2 uses N = five in words). No digits. |
| 10 | diagram: Longer windows turn later | conceptual. Conceptual (no numbers) | Conceptual sketch of lag: price bottoms at x = 0.5; the short average bottoms later (≈0.6) and the long one later still (≈0.72), both staying above a V-shaped price as smoothed averages do. No numbers. Replaces decorative hourglass. |
| 11 | compare: Price and its average are not in step | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 11. |
| 13 | diagram: A crossover: price passes through its average | conceptual. Conceptual (no numbers) | Two straight segments (not smoothed): price y = 0.2 + 0.7222(x − 0.05), average y = 0.4 + 0.2222(x − 0.05); they meet where 0.5(x − 0.05) = 0.2, x = 0.45, y = 0.489, where the dot sits. Conceptual. |
| 14 | flow: Why a crossover happens | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 14: a crossing is the mechanical result of recent closes versus the older closes in the window (beat 3: each day drops the oldest, adds the newest). |
| 15 | compare: Arithmetic versus an open question | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 15: whether a crossing bears on future prices is a separate, empirical question (lesson 4 evidence). Replaces decorative question mark. |
| 21 | flow: Before trusting an unusual price | conceptual. Conceptual (no numbers) | Conceptual chain restating beats 20–21 (a single low-volume after-hours trade can print a price far from the close). Descriptive of what readers do, not advice. Replaces decorative magnifying glass. |

### rpc-06 — Patterns Are Not Predictions

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: The eye draws a trend through wiggles | conceptual. Conceptual (no numbers) | Conceptual: a zigzag series with a straight 'trend' the eye supplies, introducing beat 1 ('eyes are built to find shapes'). No numbers. Replaces decorative eye symbol. |
| 5 | flow: A random walk, step by step | conceptual. Conceptual (no numbers) | Conceptual cycle restating beat 2's recipe (coin flip, add or subtract) and the term (next change independent of past changes). Breaks the 4-beat chart run. |
| 8 | compare: Hindsight bias | conceptual. Conceptual (no numbers) | Conceptual restatement of the term. Replaces one of seven repeats of the four-trap flow (kept on beat 7 as the overview). |
| 9 | flow: How data-mining finds lucky rules | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 9 (test enough rules and some look brilliant by luck). |
| 10 | compare: A chance fit looks like a real one | conceptual. Conceptual (no numbers) | Conceptual restatement of the term (fit found by chance, mistaken for a real relationship). |
| 11 | compare: Survivorship: failures drop out | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 11. |
| 12 | flow: Survivorship bias | conceptual. Conceptual (no numbers) | Conceptual chain restating the term. |
| 13 | flow: Costs come out of every trade | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 13 (spread, often a commission, sometimes tax; a rule must be right by a wide margin to break even). No figures. |
| 17 | flow: Why a public pattern is already priced | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 17 ('on this view' is on the beat text). |
| 18 | compare: The efficient-markets idea, in dispute | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 18. |
| 19 | diagram: Day trading: bought and sold within one day | conceptual. Conceptual (no numbers) | Conceptual: both trades fall inside one trading day (the beat's definition). Bought and sold at the same height on purpose, so the drawing implies neither a gain nor a loss; beats 20–21 state the risk. |
| 21 | flow: Frequent intraday trading, per FINRA | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 21 (FINRA). |
| 23 | compare: What a chart shows and leaves out | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 23. Replaces decorative question mark. |
| 24 | compare: A reading vocabulary, not an edge | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 24 (vocabulary for following market reporting, not an edge over participants with the same vocabulary and faster tools). |
| 25 | flow: Risk remains after reading a chart | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 25 (SEC definition of risk). Replaces decorative shield. |

### rpc-07 — Volume and Confirmation

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: One use of volume | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 1. Replaces decorative symbol. |
| 5 | flow: How readers apply the confirmed label | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 3 and the term (a label chart readers use, not a verdict). |
| 8 | bars: Relative volume of 2.0 and 0.6 | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; U.S. Securities and Exchange Commission, Investor.gov) | fromLesson: 2.0 (twice the recent average) and 0.6 (60 percent of it) are both stated on beat 8; bar lengths are in the stated 2.0 : 0.6 ratio. Replaces a text compare. |
| 9 | flow: The window is a choice | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 9 (a 20- or 50-day window gives a different ratio for the same day); no figures printed to avoid implying specific ratios. Replaces decorative ruler. |
| 11 | bars: Volume on the two break days, millions of units | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; U.S. Securities and Exchange Commission, Investor.gov) | fromLesson: day 11 0.9 million, about 0.6× (beat 10, the beat before) and day 18 3.0 million, about 2.2× (beat 11). Recomputed from chart rpc-07-volume: 0.9/1.47 = 0.61, 3.0/1.37 = 2.19. The chart stays on beats 10 and 12, so the lesson's candle chart is still shown; this breaks the chart run with the two figures the text states. |
| 15 | compare: Every unit bought was also sold | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 15 (volume alone cannot say which side was more eager). Replaces decorative symbol. |
| 16 | flow: A confirmation rule sorts after the fact | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 16. |
| 21 | flow: The Campbell, Grossman and Wang model | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 21 (NBER WP 4193 model mechanism). |
| 22 | compare: In their model: two kinds of price drop | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 22: a drop on a heavy-volume day is more often linked to a rise in expected return than a drop on a light-volume day. Comparative only, as in the text. |
| 25 | compare: Llorente, Michaely, Saar and Wang | conceptual. Conceptual (no numbers) | Conceptual restatement of beats 23–25 (NBER WP 8312): risk-sharing moves tend to reverse, information moves tend to continue; daily individual-stock evidence reported as consistent. |
| 26 | compare: What a volume bar cannot split | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 26. Replaces decorative question mark. |
| 28 | compare: Liquidity | conceptual. Conceptual (no numbers) | Conceptual restatement of beats 27–28 (Investor.gov: how rapidly shares can be bought or sold without substantially moving the price; low-liquidity stocks may be difficult to sell). |

### rpc-08 — Drawing Trend Lines

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: Higher lows joined by a trend line | conceptual. Conceptual (no numbers) | Conceptual: zigzag with higher lows (0.25, 0.35, 0.5) and higher highs (0.5, 0.65, 0.8); dashed line through the first two lows (slope 0.4) stays under the third low (line 0.47 at x = 0.6). Replaces decorative ruler. |
| 3 | diagram: In a downtrend the line runs over falling highs | conceptual. Conceptual (no numbers) | Conceptual mirror of beat 1 (y → 1 − y): lower highs 0.75, 0.65, 0.5 with the line through the first two (slope −0.4) above the third (line 0.53 at x = 0.6). Covers the term's downtrend half. |
| 4 | diagram: Two lows define the line; a third touch fits it | conceptual. Conceptual (no numbers) | Conceptual: line y = 0.2 + 0.5(x − 0.05) passes exactly through all three lows (0.225, 0.4, 0.575). Two points fix the line; the third only touches it. |
| 5 | diagram: Past the last price, the line is only extended slope | conceptual. Conceptual (no numbers) | Conceptual: the price ends at x = 0.6; the dashed extension continues the same slope 0.5 (0.5 + 0.5 × 0.35 = 0.675) with no price beyond it, so nothing is projected. Replaces decorative arrow. |
| 6 | diagram: Change one anchor and the slope changes | conceptual. Conceptual (no numbers) | Conceptual: both lines start at the first low (0.1, 0.2). Through the middle low (0.4, 0.38): slope 0.6. Through the latest low (0.75, 0.45): slope 0.385, and the middle low lies above it (line 0.315 < 0.38). Breaks the 4-beat run of trendline-anchors (which stays on beats 2, 7, 8, 9 that say 'in the diagram'). |
| 12 | line: Two lines from the day 3 low: 0.3 and 0.2 per day | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; U.S. Securities and Exchange Commission, Investor.gov); derived 1.8 = 0.3 * (9 - 3), 3.6 = 0.3 * (15 - 3), 5.7 = 0.3 * (22 - 3), 2.4 = 0.2 * (15 - 3), 3.8 = 0.2 * (22 - 3) | fromLesson + derived: slopes 0.3 and 0.2 per day and days 3, 9, 15, 22 are stated (beats 11–14). Rise = slope × (day − 3). Cross-check with the chart's marked lows 97.0 (day 3), 98.8 (day 9), 99.4 (day 15): 97.0 + 1.8 = 98.8 and 97.0 + 2.4 = 99.4; steeper line on day 20 = 97.0 + 0.3 × 17 = 102.1, as beat 16 states. Plotted as rise since day 3 because absolute anchor prices appear only as chart marker labels, not in the prose. Chart rpc-08-anchors stays on 11, 13, 14, 16, 17, 23. |
| 15 | candles: Low below the line, close above it | illustrative. Illustrative, not real data (labelled in the app) | Illustrative single candle using the lesson chart's day 20 (open 102.3, high 102.5, low 101.7, close 102.2) with the steeper line's value that day, 102.1 (beat 16): low 101.7 < 102.1 < close 102.2, so the intraday rule counts a break and the closing rule does not. The horizontal line stands in for the sloped line at a single day. Basis illustrative because open and high are not stated in the prose. |
| 18 | candles: A close below a level, reversed soon after | illustrative. Illustrative, not real data (labelled in the app) | Low 100.0 on c2 held the level; c6 closes 99.6 below 100; c7 closes 100.8 back above and later closes stay above. The label is applied to a completed past sequence, matching the term's 'labeled only in hindsight'. Replaces decorative symbol. |
| 19 | compare: Which break counts depends on the rule | conceptual. Conceptual (no numbers) | Conceptual restatement of beats 15 and 19 (which rule; verdict known only later). Replaces decorative hourglass. |
| 25 | compare: The eye versus a fixed procedure | conceptual. Conceptual (no numbers) | Conceptual restatement of beats 25–27 (researchers replace the eye with fixed procedures; shapes depend on who is looking). Replaces decorative eye. |
| 28 | compare: Ordinary and logarithmic price axes | conceptual. Conceptual (no numbers) | Conceptual: row 1 is the term's definition; row 2 follows from it (a straight line on an axis of equal price steps adds equal price amounts; on a log axis it grows by equal percentages). |
| 29 | diagram: Same two lows: log-axis line seen on an ordinary axis | conceptual. Conceptual (no numbers) | Both lines pass through the same lows (0.1, 0.15) and (0.5, 0.3). Straight: slope 0.375, 0.469 at x = 0.95. A straight line on a log axis is exponential on an ordinary axis: y = 0.15 × 2^((x − 0.1)/0.4), giving 0.212, 0.3, 0.424, 0.654; it lies below the straight line between the lows and above it afterward, so a price can cross the two on different days (beat 29). |

### rpc-09 — Base Rates: Judging a Pattern's Record

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 2 | flow: Base rate | conceptual. Conceptual (no numbers) | Conceptual chain restating the term. |
| 3 | flow: Conditional frequency | conceptual. Conceptual (no numbers) | Conceptual chain restating the term; parallel to beat 2 so the two can be compared on beat 4. |
| 6 | bars: Price higher afterward: 55% either way | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 11/20 = 0.55 and 44/80 = 0.55, both stated with 55% on beat 6. Equal bars show 'no information'. Replaces a repeat of the grid (kept on beat 5). |
| 7 | flow: A rule with no real information | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 55 percent base rate stated on beat 7. |
| 8 | proportion: Roughly 55 percent of signals rise anyway | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 55 of every 100 signals from beat 7's 55 percent base rate; the other 45 are signals not followed by a rise, i.e. false positives by the term's definition. Replaces decorative flag. |
| 14 | proportion: About 25% of 20-flip runs reach 12 heads | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 'about 25 percent' (beat 13) for 12+ heads in 20 fair flips (beats 12–14). Verified binomial: P(X ≥ 12 \| n = 20, p = 0.5) = 263950 / 1048576 = 0.2517. Waffle shows 25 of 100 (rounded, as the text says 'about'). |
| 15 | flow: Many tests, some lucky records | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 15. |
| 16 | flow: A base-rate comparison in research | conceptual. Conceptual (no numbers) | Conceptual chain restating beats 16–17 (conditional vs unconditional return distributions). Replaces decorative doc symbol. |
| 19 | compare: Multiple testing raises the bar | conceptual. Conceptual (no numbers) | Conceptual restatement of the term. |
| 21 | formula: The t-ratio | conceptual. Conceptual (no numbers) | Conceptual formula restating the term. 'SE' is named in the terms as standard error. |
| 23 | bars: t-ratio cutoff for a new factor | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 2.0 stated on beat 22, 3.0 on beat 23 (Harvey, Liu and Zhu, NBER WP 20592). Replaces a repeated compare (kept on beat 22). |
| 24 | compare: Factors and chart patterns share the problem | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 24. |
| 25 | compare: Costs can flip a thin edge | conceptual. Conceptual (no numbers) | Conceptual restatement of beat 25; the numbers follow on beats 26–28. Replaces decorative warning symbol. |
| 27 | formula: Average trade before costs: 0.05 percent | fromLesson. Restates the lesson's figures (lesson sources: National Bureau of Economic Research; Financial Industry Regulatory Authority (FINRA)) | fromLesson: 0.55 × 0.5 = 0.275; 0.45 × 0.5 = 0.225; 0.275 − 0.225 = 0.05 (percent). All figures on beat 27; 0.55 and 0.5 also on beat 26. Beat 28: 0.05 − 0.1 = −0.05, as stated. |
| 29 | flow: Frequent trading, per FINRA | conceptual. Conceptual (no numbers) | Conceptual chain restating beat 29 (FINRA: higher costs that might erode returns, potential tax implications). |

### bry-01 — Price and Yield

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: A bond is a loan you can trade | conceptual. Conceptual (no numbers) | Conceptual flow, no numbers. Restates beat 1: an issuer (government, city or company) borrows through a tradable certificate. |
| 4 | formula: The coupon, in dollars a year | conceptual. Conceptual (no numbers) | Conceptual formula. Beat 4 defines the coupon as a yearly percentage of face value, so yearly coupon dollars = coupon rate × face value. No example, because $40 and 4 percent are first stated on beat 9. |
| 5 | flow: From issue to maturity | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 5 (maturity: the loan ends and face value is repaid). The coupon schedule comes from beat 4's 'paid on a set schedule'. |
| 7 | flow: What goes into a bond's yield | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 7's definition: yield is the return at the price paid, counting coupons and the face value repaid at maturity. |
| 8 | compare: What is fixed and what moves | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 8: the coupon never changes; the traded price does. |
| 10 | bars: At $1,000, the old bond yields less | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect); derived 4 = 40 / 1000 * 100 | fromLesson bars. Beat 9: $1,000 face, 4 percent coupon, $40 a year. Beat 10: new bonds pay 5 percent. At a $1,000 price the old bond's simple yield is 40/1000 = 4% (derived, the simple-yield method of beat 14). New bonds issued at par yield their 5 percent coupon. |
| 12 | diagram: Lower going yields push the old bond's price up | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 12 ('the reverse holds'). It is the convex price-yield shape of the lesson chart: when new bonds pay less, the old bond's price rises. The dot sits where the going yield equals the coupon (par). No specific prices are drawn, because a full price needs a maturity beat 12 does not give. |
| 15 | diagram: Price is pulled toward face value near maturity | conceptual. Conceptual (no numbers) | Conceptual pull-to-par diagram for beat 15. With the going yield unchanged (stated in the note), a bond priced above face drifts down to face value at maturity, and one priced below drifts up. This is directionally exact for a fixed yield. |
| 20 | flow: What the issuer still owes | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect) | fromLesson flow. Beat 20 states that the issuer still owes $40 a year and $1,000 at the end. |
| 22 | diagram: The coupon-yield gap sets the price | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 22 (TreasuryDirect: price depends on the gap between the coupon and the yield buyers demand). Left of 'Yield = coupon', the coupon is above the demanded yield, so the price is above par; right of it, the price is below par. Beat 23 states the par case. |

### bry-02 — Duration and Interest-Rate Risk

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: Same yield move, bigger price swing for longer bonds | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 1. Two price-yield curves cross where the coupon equals the yield. The long-maturity curve is steeper and more convex, which matches the lesson chart (30-year −15.5/+19.7 against 2-year −1.9/+1.9). |
| 2 | flow: A two-year bond hands money back soon | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 2 (a short bond returns face value soon, so it is stuck with an old coupon only briefly). The rise in yields is beat 1's premise. |
| 4 | line: A distant payment loses more value when rates rise | computed. Computed: Lower rate = {"model":"purchasingPower","start":100,"ratePct":3,"years":30,"step":2}; Rate one point higher = {"model":"purchasingPower","start":100,"ratePct":4,"years":30,"step":2} (inputs stated in the lesson; lesson sources: U.S. Securities and Exchange Commission, Investor.gov; U.S. Department of the Treasury, TreasuryDirect) | Computed line. purchasingPower is start/(1+r)^t, which is exactly the present value of a payment due in t years. Inputs: rates 3 and 4 percent (beat 9's one-percentage-point example), 30 years (the lesson's 30-year bond), and start 100 (derived constant). Year 30: 41.20 against 30.83; year 2: 94.26 against 92.46. Distant payments lose more value when rates rise a point (beat 4). Labels carry no digits, so they do not restate beat 9's figures. |
| 6 | flow: How interest-rate risk shows up | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 6's definition of interest-rate risk. 'Matters if sold before maturity' is beat 15's point. |
| 7 | formula: Duration as a rule of thumb | conceptual. Conceptual (no numbers) | Conceptual formula: %ΔP ≈ −D × Δy, which is beat 7's definition (approximate percent price change per one-point yield change). The minus sign encodes that price falls when yield rises. |
| 10 | diagram: Duration sits before the final payment | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 10. Duration is tied to the weighted average time of the cash flows, so it falls before the final (face value) payment. The guide position is schematic. |
| 12 | diagram: A zero-coupon bond: one payment at maturity | conceptual. Conceptual (no numbers) | Lead fix (orchestrator note): the term text now says duration is close to, and slightly below, full maturity; beat 7 defines duration as percent price change per point (modified duration, T/(1+y) for a zero). The diagram's note and Duration guide (0.84, left of the single payment at 0.9) now agree. |
| 15 | diagram: Held to maturity or sold before | conceptual. Conceptual (no numbers) | Conceptual path for beat 15 (Investor.gov). Sold before maturity, a bond may fetch more or less than face value; held to maturity, it returns face value. The path is schematic. |
| 16 | compare: Two different risks | conceptual. Conceptual (no numbers) | Conceptual compare for beat 16: duration measures the price swing and says nothing about credit risk. 'Rate risk' is short for the lesson's interest-rate risk (the column head limit is 16 characters). |

### bry-03 — The Yield Curve

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | flow: One borrower's debt, shortest to longest | conceptual. Conceptual (no numbers) | Conceptual flow listing beat 1's maturities in order (a few weeks, one, two, ten, thirty years). |
| 2 | diagram: Connect the dots: the yield curve | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 2: yields plotted by maturity with the dots connected. Dots are labeled with beat 1's maturities, and the upward slope is only the example shape. |
| 3 | diagram: How much more to lend for longer? | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 3's question: the gap between the long and short yield. The note covers the downward case ('or less'). |
| 4 | line: 10-year minus 3-month spread, yearly average | sourced. FRED (data: Federal Reserve Bank of St. Louis), "10-Year Treasury Constant Maturity Minus 3-Month Treasury Constant Maturity", https://fred.stlouisfed.org/series/T10Y3MM, 1982–2025, annual average of monthly values, retrieved 2026-09-15; series T10Y3MM | Sourced: FRED T10Y3MM (Federal Reserve Bank of St. Louis, Interest Rate Spreads release), annual mean of monthly values, 1982–2025, 44 points. Supports 'most of the time the line slopes upward'. Yearly averages are below zero only in 2006 (−0.06), 2023 (−1.32) and 2024 (−0.97). By month, 479 of 536 readings from Jan 1982 to Aug 2026 are ≥ 0. The note says yearly averages hide brief dips (for example 1989, 2000 and 2019). Beat 4 states no figure, so nothing can disagree. |
| 6 | diagram: Expectations plus a term premium | conceptual. Conceptual (no numbers) | Conceptual diagram of beats 5–6. The long yield is the average expected short rate (dashed) plus a term premium (the gap). Directionally exact. |
| 7 | formula: What a long yield bundles together | conceptual. Conceptual (no numbers) | Conceptual formula restating the term-premium idea: long yield ≈ expected average short rate + term premium (beats 5–7). |
| 14 | flow: How Treasury builds its par yield curve | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 14 (Treasury FAQ): built from closing bid quotes and read at fixed maturity points. |
| 16 | flow: What one point on the par curve means | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 16's definition: each par-curve point is the coupon rate at which a bond of that maturity would trade at face value. |

### bry-04 — Inversions and What They Have Signaled

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 7 | formula: Recall: what a long yield bundles | conceptual. Conceptual (no numbers) | Conceptual formula recalling bry-03, as beat 7 does: long yield ≈ expected average short rate + term premium. |
| 8 | diagram: If markets expect the short rate to be cut | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 8's hypothetical: the expected short-rate path falls from its starting level. It shows expectations only and makes no forecast. |
| 10 | diagram: An inverted curve can reflect expected cuts | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 10. If the expected path falls, the average of that path over a longer horizon is lower, so the curve slopes down while sitting above the path. A positive term premium only lifts the curve. |
| 11 | flow: A guess shaped by many forces | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 11: the guess reflects growth and many other influences, and can turn out right or wrong. |
| 15 | line: The 2022–2024 inversion, month by month | sourced. FRED (data: Federal Reserve Bank of St. Louis), "10-Year Treasury Constant Maturity Minus 3-Month Treasury Constant Maturity", https://fred.stlouisfed.org/series/T10Y3MM, January 2021–December 2024, monthly, retrieved 2026-09-15; series T10Y3MM | Sourced: FRED T10Y3MM, all monthly values Jan 2021–Dec 2024 (48 points). Beat 15 says the long inversion ran from late 2022 through late 2024. The data is negative every month from Nov 2022 (−0.43) through Nov 2024 (−0.26); Oct 2022 is +0.11 and Dec 2024 is 0.00. Markers sit on those two data points. The window stops at Dec 2024 because the beat describes that run; brief small monthly dips recurred in 2025 (for example Mar −0.06, Aug −0.04). The graphic makes no statement about any recession. |
| 18 | compare: Association is not prediction | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 18: the record describes the past, has exceptions, and is not a forecast or rule. |
| 19 | compare: What followed past inversions | fromLesson. Restates the lesson's figures (lesson sources: Federal Reserve Bank of Cleveland; Federal Reserve Bank of San Francisco) | fromLesson compare for beat 19: gaps from a few months to about two years ('2' is beat 19's 'two'), and some inversions with no recession. 'Most past cases' is supported by beat 13 (all but one) and beats 14–15 (8 recessions, 3 notable false signals). |
| 21 | compare: Researchers read the signal differently | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 21: some Reserve Bank researchers urge caution against a literal reading; others find the record holds up. |
| 22 | compare: What this lesson does and does not do | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 22: the lesson explains why the spread is watched and makes no forecast. |

### bry-05 — Real vs Nominal

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | compare: Two ways to count a yield | conceptual. Conceptual (no numbers) | Conceptual compare for beat 1: nominal yield counts dollars and says nothing about what they buy. Real yield is named ahead of beat 5. |
| 3 | diagram: Rising prices shrink what a dollar buys | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 3: a sustained rise in prices lowers what a dollar buys over time. |
| 5 | formula: Real yield, as a rule of thumb | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury) | fromLesson formula for beat 5 (real ≈ nominal − inflation). Example 5% − 3% ≈ 2% is beat 4's stated case. |
| 6 | diagram: When inflation tops the yield, real yield turns negative | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 6. Real yield ≈ nominal − inflation is a line of slope −1 in inflation, crossing zero where inflation equals the nominal yield; beyond that it is negative. |
| 10 | line: A 4% yield when prices rise 5% a year | computed. Computed: Balance at 4%, reinvested = {"model":"compound","principal":100,"ratePct":4,"years":10,"step":1}; What it buys, start prices = {"model":"purchasingPower","start":100,"ratePct":0.961538,"years":10,"step":1} (inputs stated in the lesson; lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury) | Computed line. The previous beat (check 9) states a 4 percent nominal yield and 5 percent inflation. Balance = compound(100, 4%, 10 years). Buying power = balance ÷ price level = 100·(1.04/1.05)^t = purchasingPower(100, r) with r derived as (1.05/1.04 − 1)×100 = 0.961538%. Year 10: balance 148.02, buying power 90.87, so the dollars grew but buy less (beats 6 and 10). Start 100 is a derived constant; 10 years is the lesson's 10-year TIPS maturity. |
| 12 | compare: What TIPS change | conceptual. Conceptual (no numbers) | Conceptual compare for the TIPS term (beat 12) against beat 10's ordinary bond: principal fixed in dollars against principal moving with a price index; return set in nominal against real terms. |
| 14 | formula: Fixed rate, moving interest payment | conceptual. Conceptual (no numbers) | Conceptual formula for beat 14: interest payment = fixed coupon rate × adjusted principal. |
| 16 | compare: A 3% index rise, in dollars | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury); derived 1030 = 1000 * (1 + 3 / 100), 10.3 = 1030 / 100 | fromLesson compare. Beats 15–16: $1,000 principal, 1% coupon, index +3%, principal about $1,030, interest about $10.30 instead of $10.00. Derived: 1000×1.03 = 1030; 1030×1% = 10.30. |
| 17 | diagram: At maturity: the greater of the two principals | conceptual. Conceptual (no numbers) | Conceptual payoff diagram for beat 17: at maturity the holder gets the greater of adjusted and original principal. Below an unchanged index the lower adjusted principal (dashed) is not paid; the floor is the original principal. |
| 21 | diagram: Two curves from the same source | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 21: the Treasury publishes a nominal and a real par yield curve side by side. The real curve is drawn below the nominal one, as it is whenever breakeven inflation is positive. The shape is schematic. |

### bry-06 — The Policy Rate and the Curve

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: The central bank anchors the short end | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 1: the very short end of the curve is anchored by the central bank. |
| 3 | diagram: A target range for the overnight rate | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 3's term: the FOMC sets a target range, and the overnight federal funds rate trades within it. |
| 4 | flow: Tools that hold the rate in range | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 4's tools (interest on reserves, open market purchases and sales) that keep the overnight rate in range. |
| 6 | compare: Who sets which rate | conceptual. Conceptual (no numbers) | Conceptual compare for beats 5–7: the policy rate is set by the FOMC's decision; longer yields come from market trading and reflect expected rates plus a term premium. |
| 10 | line: Policy rate and 10-year yield, 2021–2025 | sourced. FRED (data: Board of Governors of the Federal Reserve System), "Federal Funds Effective Rate; Market Yield on U.S. Treasury Securities at 10-Year Constant Maturity, Quoted on an Investment Basis", https://fred.stlouisfed.org/series/FEDFUNDS, January 2021–December 2025, monthly, retrieved 2026-09-15; series FEDFUNDS, GS10 | Sourced: FRED FEDFUNDS (Federal Funds Effective Rate) and GS10 (Market Yield on U.S. Treasury Securities at 10-Year Constant Maturity), both Board of Governors H.15, monthly, Jan 2021–Dec 2025, 60 points each. It illustrates beat 10: in the 2022–23 tightening the funds rate rose about 5.25 points (0.08 → 5.33) while the 10-year rose less (1.76 in Jan 2022, peak 4.80 in Oct 2023). The funds rate was above the 10-year every month from Dec 2022 (4.10 against 3.62) to Dec 2024 (4.48 against 4.39). After the late-2024 cuts, the 10-year was back above it from Jan 2025 (4.33 against 4.63). No lesson figure covers this period (the lesson chart is illustrative, on beats 12–13). No markers, no forecast. |
| 11 | diagram: Two ends, moved by different forces | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 11's seesaw: the central bank moves the short end; expectations move the long end. |
| 14 | flow: From the policy rate to households | conceptual. Conceptual (no numbers) | Conceptual flow for beat 14: other rates are priced off the curve the policy rate anchors, and households borrow and save at those rates. |
| 15 | flow: The short end responds quickly | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 15: savings, money market funds and short CDs track the short end and move soon after the FOMC acts. |
| 16 | compare: Priced off different ends of the curve | fromLesson. Restates the lesson's figures (lesson sources: Board of Governors of the Federal Reserve System) | fromLesson compare for beats 15–16: a savings account tracks the short end and moves with FOMC action; a 30-year fixed mortgage is priced near long Treasury yields and moves on expectations. |
| 20 | diagram: Which end does a rate belong to? | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 20: ask which end of the curve a rate belongs to. |
| 21 | diagram: Near the short end: follows the policy rate | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 21: credit cards and savings rates sit near the short end. |
| 22 | diagram: Near the long end: follows expectations | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 22: long mortgages and long-term borrowing costs sit near the long end. |

### bry-07 — Credit Spreads

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 1 | diagram: Treasury yields: the ruler for other borrowers | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 1: Treasury yields are the benchmark curve, and company bonds are measured above it. |
| 2 | compare: Same maturity, different borrower | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Board of Governors of the Federal Reserve System) | fromLesson compare restating beat 2: a company's 10-year bond must offer more than the 10-year Treasury. |
| 6 | formula: How the Board's report measures spreads | conceptual. Conceptual (no numbers) | Conceptual formula for beat 6 (the Board report tracks corporate yields over comparable-maturity Treasury yields): spread = company yield − Treasury yield. The quiz's own figures (4.0, 5.1, 7.2) are deliberately not shown before check beat 12. |
| 7 | flow: What default means for a bondholder | conceptual. Conceptual (no numbers) | Conceptual flow for beat 7's definition of default risk (a failure to make timely interest or principal payments), which one piece of the spread pays for. |
| 8 | flow: How a credit rating works | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 8 (SEC bulletin): agencies evaluate default risk, assign ratings and may revise them. |
| 10 | compare: Two sides of the rating split | conceptual. Conceptual (no numbers) | Conceptual compare for beats 9–11 (SEC ratings bulletin): on scales that split between BBB and BB, BBB- or higher is investment grade and lower is high yield, which generally pays more. |
| 13 | compare: What a credit rating reflects | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 13: a rating does not reflect market or liquidity risk, and even top-rated debt sometimes defaults. |
| 14 | compare: More and less liquid bonds | conceptual. Conceptual (no numbers) | Conceptual compare for beat 14 (SEC bulletin): bonds that trade often and in high volumes may be more liquid. Hedged 'Often easier/harder'. |
| 15 | flow: Liquidity risk | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 15's definition of liquidity risk (the bulletin's wording). |
| 16 | flow: Call risk | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 16: call risk, where the company may buy the bond back before maturity. |
| 21 | flow: What the Board's 2020 report records | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Board of Governors of the Federal Reserve System) | fromLesson flow restating beat 21: the Board's 2020 annual report says spreads over comparable-maturity Treasury yields increased significantly early in the pandemic (2020). |
| 24 | timeline: Early 2020: widening, then a facility | fromLesson. Restates the lesson's figures (lesson sources: U.S. Securities and Exchange Commission, Investor.gov; Board of Governors of the Federal Reserve System) | fromLesson timeline. Early 2020: spreads widened while new issuance halted (beats 21–23, Board report and FEDS Notes, Oct 7, 2020). Mar 23, 2020: the Fed and the Treasury announced a corporate bond buying facility, and spreads eased substantially in the following days, before any bond was bought (beat 24). Only dates the lesson states. |

### bry-08 — Breakeven Inflation and the Real Yield Curve

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 2 | compare: Where inflation shows up | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 2: nominal yields are stated in dollars and must cover inflation; TIPS yields are real, because inflation is paid through the principal adjustment. |
| 5 | bars: Nominal minus TIPS yield: the breakeven | fromLesson. Restates the lesson's figures (lesson sources: Board of Governors of the Federal Reserve System; Federal Reserve Bank of St. Louis, FRED; U.S. Department of the Treasury; U.S. Department of the Treasury, TreasuryDirect); derived 2.4 = 4.30 - 1.90 | fromLesson bars. Beat 5: illustrative 10-year note 4.30%, TIPS 1.90%, breakeven 4.30 − 1.90 = 2.40 points (derived). This replaces the stat with the three quantities. |
| 6 | line: 10-year breakeven inflation rate, yearly average | sourced. FRED (data: Federal Reserve Bank of St. Louis), "10-Year Breakeven Inflation Rate", https://fred.stlouisfed.org/series/T10YIEM, 2003–2025, annual average of monthly values, retrieved 2026-09-15; series T10YIEM | Sourced: FRED T10YIEM (10-Year Breakeven Inflation Rate, monthly; Federal Reserve Bank of St. Louis, Interest Rate Spreads release), annual mean of monthly values, 2003–2025, 23 points. Beat 6 names FRED's daily 10-Year Breakeven Inflation Rate (T10YIE); T10YIEM is its monthly version (daily series cannot be sampled by the recipe), and the note says yearly average. Cross-check against the two H.15 series: 2003 GS10 4.01 − FII10 2.06 = 1.95 against T10YIEM 1.96; 2021 1.44 − (−0.92) = 2.36 against 2.36. No figure on beat 6 or 7. Beat 5's 2.40 is labelled illustrative and has no period, so it cannot conflict. |
| 7 | formula: How FRED's breakeven series is built | fromLesson. Restates the lesson's figures (lesson sources: Board of Governors of the Federal Reserve System; Federal Reserve Bank of St. Louis, FRED; U.S. Department of the Treasury; U.S. Department of the Treasury, TreasuryDirect) | fromLesson formula restating beat 7: FRED's breakeven is derived from 10-year nominal and inflation-indexed constant maturity Treasury yields (FRED page: comparing the two). |
| 10 | formula: Inflation compensation in the Board note's model | conceptual. Conceptual (no numbers) | Conceptual formula restating beat 9's model (Board FEDS Note): inflation compensation = expected inflation + inflation risk premium − TIPS liquidity premium. Beat 10 defines IRP. |
| 11 | diagram: The inflation risk premium over the decades | illustrative. Illustrative, not real data (labelled in the app) | Illustrative shape for beat 11: the inflation risk premium is believed positive and sizable in the 1970s and 1980s and appears to have declined to lower or even negative levels. Shape only (no values), stated in the note. The decades are the beat's. |
| 12 | compare: Why TIPS carry a liquidity premium | conceptual. Conceptual (no numbers) | Conceptual compare for beat 12's term: TIPS are less liquid than nominal Treasuries, so they carry extra yield. |
| 14 | diagram: Which premium is larger decides the gap | conceptual. Conceptual (no numbers) | Conceptual diagram of beats 13–14: the risk premium pushes breakeven above expected inflation and the liquidity premium pushes it below, so the net depends on which is larger. |
| 16 | diagram: Par real yield curve, beside the nominal one | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 16: the Treasury's par real yield curve, published next to the nominal par curve. The shape is schematic; the real curve is drawn below the nominal one (positive breakeven). |
| 18 | line: 10-year TIPS real yield, yearly average | sourced. FRED (data: Board of Governors of the Federal Reserve System), "Market Yield on U.S. Treasury Securities at 10-Year Constant Maturity, Quoted on an Investment Basis, Inflation-Indexed", https://fred.stlouisfed.org/series/FII10, 2003–2025, annual average of monthly values, retrieved 2026-09-15; series FII10 | Sourced: FRED FII10 (Market Yield on U.S. Treasury Securities at 10-Year Constant Maturity, Quoted on an Investment Basis, Inflation-Indexed; Board of Governors H.15), annual mean of monthly values, 2003–2025, 23 points, with a zero reference. Beat 18: a real yield can fall below zero. Yearly averages are negative in exactly 2012 (−0.48), 2020 (−0.60) and 2021 (−0.92), as the note says; 2013 is +0.07. Monthly readings were negative Dec 2011–May 2013 and Feb 2020–Apr 2022. No lesson figure for these years; the check's −0.4 percent is illustrative. |
| 19 | flow: Treasury's 0.125 percent floor rule | fromLesson. Restates the lesson's figures (lesson sources: Board of Governors of the Federal Reserve System; Federal Reserve Bank of St. Louis, FRED; U.S. Department of the Treasury; U.S. Department of the Treasury, TreasuryDirect) | fromLesson flow restating beat 19: under the rule amended in April 2011, an auction yield below 0.125% gets a 0.125% interest rate, with the price adjusted to a premium. |
| 20 | diagram: Paying above par pulls the yield below zero | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 20. With a small positive coupon, the yield at par is slightly above zero; paying more than par pulls it below zero. The curve crosses the zero guide just right of par. The shape is schematic. |

### bry-09 — Treasury Auctions

| Beat | Graphic | Basis and source | Review note |
|---|---|---|---|
| 2 | diagram: Dates named in an auction announcement | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 2: the announcement names the auction, issue and maturity dates (the other items are in the note). |
| 3 | flow: Auction first, issue later | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 3: auction date and issue date are often a few days or even a few weeks apart. |
| 6 | compare: Two ways to bid | conceptual. Conceptual (no numbers) | Conceptual compare for beats 4–6: noncompetitive bids name an amount only and may be placed through TreasuryDirect (beat 5); competitive bids name a rate, yield or discount margin and go through a bank, broker or dealer. |
| 8 | flow: The order of acceptance | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 8: all compliant noncompetitive bids first, then competitive bids from the lowest yield upward until the offering is awarded. |
| 9 | diagram: The high yield, or stop | conceptual. Conceptual (no numbers) | Conceptual diagram of beat 9: cumulative bids by yield; the highest accepted yield, where they reach the offering amount, is the high yield ('stop'). |
| 11 | compare: One yield, one price for every winner | conceptual. Conceptual (no numbers) | Conceptual compare restating beat 11: every successful bidder receives the high yield and pays the single price. |
| 13 | proportion: How the $30 billion offering is filled | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury, Bureau of the Fiscal Service; Federal Reserve Bank of New York) | fromLesson proportion. Beats 12–13: $30 billion offering = $1.5B noncompetitive + $27.0B of bids at 4.20–4.25% + $1.5B of the $5.0B bid at 4.26%. 1.5 + 27 + 1.5 = 30, so no remainder. This matches the chart's accepted series (1.5+2.5+4+6+7+6 = 27). |
| 16 | bars: Bid-to-cover: $75.0 billion ÷ $30.0 billion | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury, Bureau of the Fiscal Service; Federal Reserve Bank of New York); derived 2.5 = 75.0 / 30.0 | fromLesson bars. Beat 16: $75.0 billion tendered, $30.0 billion accepted, bid-to-cover 75.0/30.0 = 2.50 (derived). |
| 18 | compare: Announcement versus results release | conceptual. Conceptual (no numbers) | Conceptual compare for beat 18. The announcement contents are from beat 2; the results release contents (high yield, allotment, bid-to-cover) are from beats 19–21 and the recap. |
| 19 | proportion: Bids at the 4.342% high yield: 92.86% allotted | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury, Bureau of the Fiscal Service; Federal Reserve Bank of New York) | fromLesson proportion. Beat 19: the May 6, 2025 10-year note high yield was 4.342%, and bids at that yield were allotted 92.86%. |
| 20 | compare: Rate below the high yield, price below par | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury, Bureau of the Fiscal Service; Federal Reserve Bank of New York) | fromLesson compare. Beat 20: interest rate 4-1/4%, below the 4.342% high yield, so the price was 99.260100 per $100. Recomputed: 20 semiannual coupons of 2.125 at 2.171% per half-year give 99.26. |
| 21 | bars: Bid-to-cover: tendered ÷ accepted = 2.60 | fromLesson. Restates the lesson's figures (lesson sources: U.S. Department of the Treasury, TreasuryDirect; U.S. Department of the Treasury, Bureau of the Fiscal Service; Federal Reserve Bank of New York); derived 2.6 = 109378157100 / 42000007100 | fromLesson bars. Beat 21: $109,378,157,100 tendered and $42,000,007,100 accepted; 109378157100/42000007100 = 2.604, reported as 2.60 (derived). |
| 22 | flow: When-issued trading starts early | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 22 (NY Fed study): when-issued trading starts right after the auction is announced. |
| 23 | diagram: The when-issued window | conceptual. Conceptual (no numbers) | Conceptual diagram for beat 23's term: when-issued trading runs from announcement to issue, with settlement on the issue date. |
| 24 | flow: Price discovery before the auction | conceptual. Conceptual (no numbers) | Conceptual flow restating beat 24: when-issued trading serves as price discovery, giving potential bidders a gauge of demand. |
