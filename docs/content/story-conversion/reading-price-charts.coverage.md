# reading-price-charts: 1.1.4 blocks to 1.1.5 beats coverage

Block indexes match `src/reading-price-charts.txt`. Beat numbers are 1-based. Summaries are unchanged (all were 35 words or fewer). Charts are copied verbatim.
Validator: `0 error(s), 0 warning(s), 18 distinct URL(s) cited`.

## rpc-01 Candlestick Anatomy and Timeframes (21 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (chart record, candlestick, slice of time, OHLC definitions) | 1, 2, 3, 4 |
| 1 | diagram caption candle-anatomy (body open to close; wicks/shadows to high/low) | 5 (also shown on 3, 6, 11) |
| 2 | paragraph (body, up/down, color conventions, blue/amber, wicks, long wick) | 7, 8, 9, 10 |
| 3 | chart caption rpc-01-candles (one trading day; up/down close vs open; wicks mark extremes) | 9 (up/down rule on 7); chart on 8–10 |
| 4 | callout note "Which close counts?" (SEC, 9:30–4:00 ET, after-hours tagged, vendors differ, rules) | 12, 13, 15 |
| 5 | paragraph timeframe / weekly candle | 16, 17, 18, 19 |
| 6 | keyTerms Open / Close / Wick / Timeframe | 3 / 14 / 6 / 16 |
| 7 | quiz | 11 |
| 8 | takeaways | 21 (facts on 4–5, 7, 12–15, 17–19) |

- Left out: "Those four numbers" became "The four numbers" (same fact). No facts omitted.
- Added check: beat 20 (weekly candle's high), answered on beat 18.
- Quiz trimmed: question compressed to the OHLC values; choices shortened ("Up: high is above open", etc.). Right/wrong unchanged; explanation verbatim.

## rpc-02 Trends and Ranges (22 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (three words; uptrend; downtrend; range/sideways/consolidation) | 1, 3, 5, 6 |
| 1 | diagram caption trend-channel | 4 (also shown on 3, 7) |
| 2 | paragraph (description not rule; past swing points; can end any time; hindsight; 14 up / 12 sideways) | 8, 9, 10, 11 |
| 3 | chart caption rpc-02-trend-to-range (days 1–14 HH/HL; from day 15 highs near 102.6, lows near 100.5, range) | 11, 12 |
| 4 | callout example "Same data, three answers" | 13, 14, 15, 16 |
| 5 | paragraph (say which timeframe; SEC stock market definition; chart drawing of trades; facts vs interpretation) | 18, 19, 20, 21 |
| 6 | keyTerms Uptrend / Downtrend / Range / Swing high | folded as headings 3 / 5 / 6 (same definitions stated); Swing high 2 |
| 7 | quiz | 7 (verbatim) |
| 8 | takeaways | 22 |

- Left out: "Chart readers use three words" kept; "The chart below shows" became "This synthetic series" (pointer only).
- Added check: beat 17 (two-month daily chart label), answered on beat 14.
- Unsure/kept wording: beat 19 keeps the SEC definition verbatim.

## rpc-03 Support and Resistance (21 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (support, resistance, horizontal lines, idea that levels may recur) | 1, 2, 4, 5 |
| 1 | diagram caption support-resistance | 3 (also shown on 1, 2, 4, 15) |
| 2 | paragraph (market as orders; SEC market order; standing orders; clustering absorbs pressure; round numbers; previous high) | 6, 7, 8, 9, 10 |
| 3 | chart caption rpc-03-band (104 / 96; touches marked; drawn after the fact) | 11, 12 |
| 4 | callout caution "Descriptive, not predictive" | 13, 14, 16 |
| 5 | paragraph count the touches | 17, 18, 19 |
| 6 | keyTerms Support / Resistance / Round number / Breakout | 1 / 2 / 9 / 15 |
| 7 | quiz | 20 |
| 8 | takeaways | 21 |

- Left out: "Why would a level repeat?" kept as beat 6 heading (question, not a fact).
- No added check.
- Quiz trimmed: "A price turned down at about 104 four times. The fifth approach?"; choices shortened ("104 was resistance; the outcome is unknown", "Meaningless: four touches are too few"). Explanation verbatim.

## rpc-04 Common Candle Patterns and the Evidence (24 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (three shapes; doji; hammer) | 1, 2, 3, 4 |
| 1 | paragraph (engulfing; bullish; bearish reverse; names describe OHLC) | 6, 7, 8, 9 |
| 2 | chart caption rpc-04-patterns (day 6 hammer after five down days; days 12–13 bullish engulfing) | 5, 8 (chart on 3–8) |
| 3 | keyTerms Doji / Hammer / Engulfing pattern / Technical analysis | 2 / 3 / 6 / 11 |
| 4 | paragraph Lo, Mamaysky, Wang (NBER, March 2000; computer method; head-and-shoulders, double bottoms; U.S. stocks 1962–1996; statistical difference; incremental information, practical value; no single candles; not profits after costs) | 12, 13, 14, 15, 16 |
| 5 | callout caution "Information is not profit" | 18, 19, 20, 21, 22, 23 |
| 6 | quiz | 17 |
| 7 | takeaways | 24 |

- Left out: doji "so the body is a thin line" is carried by the Doji definition "leaving almost no body" plus "the wicks do the talking" (beat 2). The hammer's "small body near the top of its range" is stated through the key-term wording "near its high" (beat 3).
- Added check: beat 10 (doji), answered on beat 2.
- Quiz trimmed: question "What does the Lo, Mamaysky, and Wang finding show?" (the finding is stated on beat 15). Choices shortened: "Trading patterns reliably profits after costs", "Days after patterns differed statistically from ordinary days in their sample" (correct), "Every pattern works everywhere", "Charts can replace financial statements". Explanation verbatim.

## rpc-05 Moving Averages and Volume (22 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (raw prices; five-day SMA; drop oldest/add newest; 50/200-day windows) | 1, 2, 3, 5 |
| 1 | chart caption rpc-05-ma (smoother but late; keeps falling after price turns up, rising after it turns down) | 9 (chart on 1, 3, 7–9) |
| 2 | paragraph lag (old closes; day 16 bottom, day 18; longer window later; behind the price) | 7, 8, 10, 11 |
| 3 | callout note "Crossovers are just arithmetic" | 12, 14, 15 |
| 4 | paragraph volume (shares/contracts; bars; activity not direction; SEC low-volume after-hours print vs 4:00 p.m. close; check volume) | 16, 17, 20, 21 |
| 5 | chart caption rpc-05-volume (units each day; busy and quiet days on up and down days) | 18 |
| 6 | keyTerms Simple moving average / Lag / Volume / Crossover | 4 / 10 / 16 / 13 |
| 7 | quiz | 6 (verbatim question and choices) |
| 8 | takeaways | 22 |

- Left out: none.
- Added check: beat 19 (what volume measures), answered on beats 16–17.
- Quiz explanation trimmed to 34 words ("509 ÷ 5 = 101.8"; "barely moved though the price fell 5 points").

## rpc-06 Patterns Are Not Predictions (26 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (eyes find shapes; coin flips, start at 100; no dependence; seem to show trends) | 1, 2, 3 |
| 1 | chart caption rpc-06-random-walks (no memory; created by chance, drawn by the eye) | 4 |
| 2 | paragraph four traps | 7, 9, 11, 13 |
| 3 | callout note efficient-markets idea | 15, 16, 17, 18 |
| 4 | paragraph SEC day trading, FINRA intraday/borrowed money, SEC pump-and-dump, chart never says why | 19, 20, 21, 22, 23 |
| 5 | callout caution "Why this course teaches reading, not trading" | 24, 25 |
| 6 | keyTerms Hindsight bias / Data-mining / Survivorship bias / Random walk | 8 / 10 / 12 / 5 |
| 7 | quiz | 14 |
| 8 | takeaways | 26 |

- Left out: "Four traps follow." folded into the beat 7 heading.
- Added check: beat 6 (what made the trends in coin-flip series), answered on beat 4.
- Quiz trimmed: "A rule's twenty-year past record is strong. Why be cautious?"; choices "Twenty years is too short", "Maybe a chance fit among many tested rules, before costs" (correct), "Charting research is illegal", "Its past guarantees its future". Explanation lightly trimmed ("describes the past sample; it is not evidence about the future").
- Unsure: beat 19 defines day trading as a heading plus fragment ("Rapid buying and selling within one day to catch short moves.") to split the SEC sentence.

## rpc-07 Volume and Confirmation (30 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (lesson 5 volume; breakout; confirmed; unconfirmed/thin; broader agreement) | 1, 2, 3, 4, 5 |
| 1 | paragraph relative volume (definition; 10-day window; 2.0 and 0.6; window is a choice, 20/50-day) | 6, 7, 8, 9 |
| 2 | chart caption rpc-07-breakouts (days 1–10 ≤ 105; day 11 105.3, 0.9M, 0.6×; day 12 104.3; day 18 106.1, 3.0M, 2.2×; ends day 18) | 10, 11, 12 |
| 3 | chart caption rpc-07-volume (same 18 days; day 11 shortest, day 18 tallest; how much, not which way) | 13 |
| 4 | callout caution "Activity, not direction" | 15, 16, 17 |
| 5 | paragraph research (Campbell, Grossman, Wang 1992; model; heavy-volume drop; Llorente, Michaely, Saar, Wang 2001; risk-sharing reverse / private information continue; two U.S. exchanges; chart doesn't show which) | 19, 20, 21, 22, 23, 24, 25, 26 |
| 6 | callout note "Thin volume and liquidity" | 27, 28, 29 |
| 7 | keyTerms Relative volume / Confirmation / Thin volume / Liquidity | 6 / 5 / 14 / 28 |
| 8 | quiz | 18 |
| 9 | takeaways | 30 (5 takeaways condensed into 4 items; "confirmation rules use only past data" is on beat 16) |

- Left out: none. "Usual is measured with relative volume" kept as beat 6 text.
- No added check.
- Quiz trimmed: "Prior 10-day average: 1.5 million. Breakout day: 3.3 million. Which statement is correct?"; choices "0.45: under half the average", "2.2: certain to hold", "2.2: alone, it doesn't settle what's next" (correct), "1.8: volume rose 1.8 million". Explanation trimmed ("3.3 ÷ 1.5 = 2.2 ... one day's activity").
- Unsure: beat 19 heading "What research shows" is a label only.

## rpc-08 Drawing Trend Lines (30 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (lesson 2; uptrend line; downtrend line; two points / third touch; extension is not a forecast) | 1, 2, 4, 5 |
| 1 | diagram caption trendline-anchors (zigzag path, lows 1–3; Line A steeper; Line B shallower; dip below A not B, touches at low 3) | 7, 8, 9 (diagram also on 2, 4, 6) |
| 2 | paragraph (anchors set the slope; any two lows; steeper crossed sooner; Line A vs B readers) | 6, 8, 10 |
| 3 | chart caption rpc-08-anchors (lows days 3, 9, 15; 0.3 and 0.2 per day; lows below steeper on 15, 16, 20, 21, 22; closes below on 15, 21, 22; none below shallower) | 11, 12, 13, 14 |
| 4 | paragraph what counts as crossing (intraday vs close; day 20 101.7 / 102.1 / 102.2; day 15 and days 16–20; false break; verdict later) | 15, 16, 17, 18, 19 |
| 5 | callout note "Short dips and stop orders" | 21, 22, 23, 24 |
| 6 | callout caution "The eye is not a rule" (fixed procedures; Lo, Mamaysky, Wang 2000 subjective; systematic method; log scale) | 25, 26, 27, 28, 29 |
| 7 | keyTerms Trend line / Anchor point / False break / Logarithmic scale | 3 / 6 / 18 / 28 |
| 8 | quiz | 20 |
| 9 | takeaways | 30 (the "fixed rules in place of the eye" takeaway is on beat 25) |

- Left out: "A steeper line runs closer to the latest prices, so the price tends to cross it sooner than a shallower one" now ends "cross it sooner" (beat 8, right after Line B is called shallower).
- No added check.
- Quiz trimmed: "Trend line: 50 on day 1, 54 on day 5. Day 10 low 58.4, close 59.3. Which fits?"; choices "Line 59: intraday break only" (correct), "Line 58: no break", "Line 59: both rules break", "Line at 54". "If the line keeps its slope" was dropped from the question; the explanation gives the slope ("rises 1 per day"). Explanation trimmed to 33 words.

## rpc-09 Base Rates: Judging a Pattern's Record (30 beats)

| Block | Type | Beats |
|---|---|---|
| 0 | paragraph (55 percent claim lacks comparison; base rate; conditional frequency; must differ) | 1, 2, 3, 4 |
| 1 | diagram caption base-rate-grid (10 × 10, 100 dots, illustrative; 20 ringed; 11 filled; 44 of 80; 55% both; no information) | 5, 6 (both state 11, 20, 44, 80) |
| 2 | paragraph (rule that fires often; ~55 percent of signals; looks like success; false positives; hit rate without base rate) | 7, 8, 9 |
| 3 | callout example "Small samples" (50 percent coin; 20 flips; 12+ heads is about 25 percent; lucky 12 of 20; many rules, lesson 6) | 12, 13, 14, 15 |
| 4 | paragraph research (Lo, Mamaysky, Wang 2000, lesson 4, conditional vs unconditional, incremental information; many ideas raise bar; Harvey, Liu, Zhu 2014; t-ratio 2.0 vs 3.0; factors not patterns) | 16, 17, 18, 19, 20, 22, 23, 24 |
| 5 | callout caution "Costs can flip a thin edge" (55 percent, 0.5 percent, 0.05 percent, 0.1 percent round trip, loses 0.05 percent; FINRA) | 25, 26, 27, 28, 29 |
| 6 | keyTerms Base rate / Conditional frequency / False positive / t-ratio / Multiple testing | 2 / 3 / 8 / 21 / 19 |
| 7 | quiz | 10 (setup) + 11 (check) |
| 8 | takeaways | 30 (5 condensed into 4; "careful studies compare conditional and unconditional returns" is on beats 16–18) |

- Left out: "This is the trap of a rule that fires often" became the beat 7 heading "A rule that fires often". "Signals on many days while carrying no real information" became "signaling on many days with no real information". Quiz explanation's closing restatement ("so its 58 percent adds nothing beyond the base rate") was dropped; its first two sentences carry the facts.
- No added check.
- Structural change: the quiz setup (1,000 days; 116 of 200 signal days; 472 of the other 800 higher five days later) is on idea beat 10 (tone example). Check 11 asks "What does the comparison show?" because the full setup plus four choices cannot fit in 35 words. Choices trimmed: "58%: an 8-point edge over a coin flip", "58% versus 59%: no added information here" (correct), "Base rate 11.6% (116 of 1,000): far better", "Right 116 times, enough to show reliability".
- Unsure: beat 20 says the paper "studied factors proposed to explain differences in expected stock returns; hundreds had been proposed", and beat 22 carries "argued that, after hundreds of factors, the usual significance cutoff ... does not make sense". This splits one original sentence. Beat 16's "is one example" is connective only.
