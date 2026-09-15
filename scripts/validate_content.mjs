#!/usr/bin/env node
// EconByte content validator (1.1.4).
//
// A Node mirror of the Swift acceptance gates so content can be checked
// without an xcodebuild run (one xcodebuild at a time on the build Mac):
//
//   node scripts/validate_content.mjs packs   <file> [--fragment] [--net]
//   node scripts/validate_content.mjs courses <file> [--fragment] [--net]   (schemaVersion 2 story beats)
//   node scripts/validate_content.mjs brief   <file> [--net]
//   node scripts/validate_content.mjs curriculum <file> [--fragment] [--net]
//
// `packs` mirrors PackCatalog.validate + PackCatalogTests (structure, id
// collisions with the core catalog and other packs, approved hosts, dates,
// stale/advice wording, declared claims). `courses` mirrors CourseCatalog.validate
// + CourseCatalogTests. `brief` mirrors DailyBrief.validate. `curriculum`
// mirrors CurriculumCatalog.validate + CurriculumCatalogTests (the core 15
// topics, including the 1.0 legacy concept pins). `--fragment`
// accepts a file carrying a subset of packs/courses (a writer's draft) and skips
// the total-count checks. `--net` resolves every cited URL (GET, redirects
// followed) and reports anything that is not a final 200; some hosts refuse
// non-browser clients from this box (bls.gov, sec.gov 403) — those are reported
// as UNVERIFIABLE, not as failures, and must be checked by other means.
//
// The Swift side is authoritative; if the two ever disagree, fix this file.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const resources = path.join(repo, 'EconByte', 'Resources');

const CANONICAL_DISCLAIMER =
  'Educational content only. EconByte does not provide financial, investment, or tax advice.';

// PackCatalogTests.approvedSourceHosts, verbatim.
export const APPROVED_HOSTS = new Set([
  'www.federalreserve.gov', 'www.federalreservehistory.org',
  'www.newyorkfed.org', 'www.philadelphiafed.org', 'fred.stlouisfed.org',
  'www.bls.gov', 'www.bea.gov', 'www.census.gov',
  'fiscaldata.treasury.gov', 'home.treasury.gov', 'www.treasurydirect.gov',
  'www.irs.gov', 'www.ssa.gov', 'www.fdic.gov',
  'www.nber.org', 'www.conference-board.org', 'www.freddiemac.com',
  'www.wto.org', 'ustr.gov', 'data.worldbank.org', 'www.worldbank.org',
  'www.ecb.europa.eu', 'www.boj.or.jp', 'www.bis.org',
  'www.oecd.org', 'www.bundesbank.de',
  'www.cbo.gov', 'www.imf.org', 'www.sec.gov', 'www.investor.gov',
  'www.consumerfinance.gov', 'www.ncua.gov', 'www.sipc.org', 'www.finra.org',
  'www.dol.gov', 'www.studentaid.gov', 'studentaid.gov', 'www.medicare.gov',
  'www.healthcare.gov', 'www.fhfa.gov', 'www.stlouisfed.org', 'www.chicagofed.org',
  'www.clevelandfed.org', 'www.atlantafed.org', 'www.kansascityfed.org',
  'www.bostonfed.org', 'www.richmondfed.org', 'www.dallasfed.org',
  'www.minneapolisfed.org', 'www.sf.frb.org', 'www.frbsf.org', 'www.pbgc.gov',
  'www.usa.gov', 'www.ftc.gov', 'consumer.ftc.gov', 'www.mymoney.gov',
  // 1.1.4 additions (public primary sources for the history / world / systems
  // packs and the courses): national statistical offices and central banks
  // with open reuse terms, and archives.gov / loc.gov. NOT federalreserveeducation.org:
// a teaching site is not a primary publisher — cite the Board or federalreservehistory.org.
  'www.bankofengland.co.uk', 'ec.europa.eu', 'www.ons.gov.uk',
  'www150.statcan.gc.ca', 'www.statcan.gc.ca',
  'www.archives.gov', 'www.loc.gov', 'www.stats.gov.cn', 'www.pbc.gov.cn',
  'www.rba.gov.au', 'www.snb.ch', 'www.riksbank.se', 'www.norges-bank.no',
  'www.un.org', 'unctad.org', 'www.eia.gov', 'www.usitc.gov', 'www.fdicoig.gov',
  'www.occ.gov', 'www.fsb.org', 'www.bnm.gov.my', 'www.rbi.org.in',
  'www.bcb.gov.br', 'www.banxico.org.mx', 'www.boe.gov.uk',
]);

// Hosts the Daily Brief server and the bundled sample brief may cite. Narrower
// than the card list on purpose: official releases and open-licence statistical
// offices only. Never a commercial news site.
export const BRIEF_HOSTS = new Set([
  'www.bls.gov', 'www.bea.gov', 'www.census.gov', 'home.treasury.gov',
  'fiscaldata.treasury.gov', 'www.treasurydirect.gov', 'www.federalreserve.gov',
  'fred.stlouisfed.org', 'www.cbo.gov', 'www.eia.gov',
  'www.ecb.europa.eu', 'www.bankofengland.co.uk', 'ec.europa.eu', 'www.ons.gov.uk',
  'www150.statcan.gc.ca', 'www.statcan.gc.ca', 'www.imf.org', 'www.worldbank.org',
  'www.oecd.org', 'www.bis.org',
]);

const STALE_WORDS = [
  'currently', 'today', 'nowadays', 'recently', 'at present',
  'these days', 'this year', 'last year', 'right now', 'as of now',
];

const ADVICE_PHRASES = [
  'you should buy', 'you should sell', 'you should invest',
  'should buy', 'should sell', 'invest in', 'buy now', 'sell now',
  'guaranteed return', 'risk-free return', 'financial advice',
  'investment advice', 'we recommend', 'best investment',
  'will outperform', 'get rich', 'hot stock', 'price target',
  'portfolio allocation', 'beat the market', 'sure thing', 'act fast',
];

// Courses and the brief additionally ban named securities, trademarked index
// names, and brand names (course content must teach mechanisms, not name
// products), and prediction framing.
const NAMED_ENTITIES = [
  's&p', 'dow jones', 'nasdaq', 'russell 2000', 'ftse', 'nikkei', 'dax ',
  'bitcoin', 'ethereum', 'apple inc', 'tesla', 'amazon', 'microsoft', 'nvidia',
  'alphabet', 'google', 'meta platforms', 'berkshire', 'vanguard', 'fidelity',
  'blackrock', 'robinhood', 'schwab', 'coinbase', 'gamestop', 'netflix',
];
const PREDICTION_PHRASES = [
  'will rise', 'will fall', 'will go up', 'will go down', 'we expect', 'likely to rise',
  'likely to fall', 'is set to', 'poised to', 'should rise', 'should fall', 'our forecast',
  'we predict', 'will rally', 'will crash', 'will recover',
];

export const ALLOWED_DIAGRAMS = new Set([
  'candle-anatomy', 'risk-return-ladder', 'diversification-basket', 'price-yield-seesaw',
  'yield-curve-shapes', 'allocation-pie', 'support-resistance', 'fee-drag', 'trend-channel',
  // Phase 13 (content growth) additions:
  'rebalance-bands', 'trendline-anchors', 'base-rate-grid', 'credit-spread-stack', 'breakeven-split',
]);

export const EXPECTED_PACKS = [
  ['markets', 'com.nsantulli.econbyte.pack.markets'],
  ['personal', 'com.nsantulli.econbyte.pack.personal'],
  ['history', 'com.nsantulli.econbyte.pack.history'],
  ['world', 'com.nsantulli.econbyte.pack.world'],
  ['systems', 'com.nsantulli.econbyte.pack.systems'],
  ['personalfinance', 'com.nsantulli.econbyte.pack.personalfinance'],
];

export const EXPECTED_COURSES = [
  ['investing-approaches', 'ia'],
  ['reading-price-charts', 'rpc'],
  ['bonds-rates-yield-curve', 'bry'],
];

// Phase 13 (1.1.4 content growth): 12 cards in every core and pack topic,
// 9 lessons in every course.
export const CORE_CARDS_PER_TOPIC = 12;
export const PACK_CARDS_PER_TOPIC = 12;
export const LESSONS_PER_COURSE = 9;

// A catalog's items may carry the date of any verification pass on or after the
// catalog's floor and no later than its `verifiedOn` (the most recent pass), so
// items added in a later pass record their real retrieval date without
// restamping items that were verified earlier.
export const VERIFICATION_FLOOR = { curriculum: '2026-08-30', packs: '2026-09-14', courses: '2026-09-14' };

// CurriculumCatalogTests.approvedSourceHosts, verbatim (core cards).
export const CORE_HOSTS = new Set([
  'www.federalreserve.gov', 'www.federalreservehistory.org',
  'www.newyorkfed.org', 'www.philadelphiafed.org', 'fred.stlouisfed.org',
  'www.bls.gov', 'www.bea.gov', 'www.census.gov',
  'fiscaldata.treasury.gov', 'home.treasury.gov', 'www.treasurydirect.gov',
  'www.irs.gov', 'www.ssa.gov', 'www.fdic.gov',
  'www.nber.org', 'www.conference-board.org', 'www.freddiemac.com',
  'www.wto.org', 'ustr.gov', 'data.worldbank.org', 'www.worldbank.org',
  'www.ecb.europa.eu', 'www.boj.or.jp', 'www.bis.org',
  'www.oecd.org', 'www.bundesbank.de',
  // Phase 13 additions (primary publishers already approved for packs):
  'www.cbo.gov', 'www.imf.org', 'www.eia.gov', 'www.fhfa.gov', 'www.consumerfinance.gov',
  'www.stlouisfed.org', 'www.clevelandfed.org', 'www.atlantafed.org', 'www.chicagofed.org',
  'www.kansascityfed.org', 'www.bostonfed.org', 'www.richmondfed.org', 'www.dallasfed.org',
  'www.minneapolisfed.org', 'www.frbsf.org',
]);

// ProCoursesBriefTests.approvedSourceHosts, verbatim (course lessons).
export const COURSE_HOSTS = new Set([
  'www.federalreserve.gov', 'www.federalreservehistory.org',
  'www.newyorkfed.org', 'www.philadelphiafed.org', 'fred.stlouisfed.org', 'www.stlouisfed.org',
  'www.chicagofed.org', 'www.clevelandfed.org', 'www.atlantafed.org', 'www.kansascityfed.org',
  'www.bostonfed.org', 'www.richmondfed.org', 'www.dallasfed.org', 'www.minneapolisfed.org',
  'www.sf.frb.org', 'www.frbsf.org',
  'www.bls.gov', 'www.bea.gov', 'www.census.gov',
  'fiscaldata.treasury.gov', 'home.treasury.gov', 'www.treasurydirect.gov',
  'www.irs.gov', 'www.ssa.gov', 'www.fdic.gov', 'www.nber.org',
  'www.cbo.gov', 'www.imf.org', 'www.sec.gov', 'www.investor.gov',
  'www.consumerfinance.gov', 'www.finra.org', 'www.sipc.org',
]);

// CurriculumCatalogTests.legacyConcepts: the concept each 1.0 card id taught and
// tokens (in title + definition) that concept cannot be expressed without.
export const LEGACY_PINS = {"inf-001": ["What is Inflation?",["purchasing power","prices"]],"inf-002": ["The Consumer Price Index (CPI)",["consumer price index","basket"]],"inf-003": ["Core vs. Headline Inflation",["core","headline"]],"inf-004": ["Demand-Pull Inflation",["demand-pull"]],"inf-005": ["Cost-Push Inflation",["cost-push"]],"inf-006": ["Hyperinflation",["hyperinflation"]],"inf-007": ["Deflation: The Opposite Problem",["deflation","sustained fall"]],"inf-008": ["The Fed's 2% Inflation Target",["low but positive","buffer"]],"ir-001": ["What is an Interest Rate?",["price of borrowing","lenders receive"]],"ir-002": ["The Federal Funds Rate",["federal funds rate"]],"ir-003": ["Real vs. Nominal Interest Rates",["nominal rate","subtracts inflation"]],"ir-004": ["How Rates Cool Inflation",["borrowing costs","demand"]],"ir-005": ["The Yield Curve",["yield curve","inverted"]],"ir-006": ["Zero Interest Rate Policy (ZIRP)",["lower bound","physical cash"]],"ir-007": ["Credit Card Rates vs. The Fed",["revolving credit","reprice"]],"ir-008": ["Negative Interest Rates",["below zero","excess reserves"]],"gdp-001": ["What is GDP?",["gross domestic product","produced"]],"gdp-002": ["The Four Components of GDP",["consumption","net exports"]],"gdp-003": ["Real vs. Nominal GDP",["nominal gdp","base year"]],"gdp-004": ["GDP Per Capita",["per capita","population"]],"gdp-005": ["Recession: Two Quarters of Negative GDP",["two consecutive quarters"]],"gdp-006": ["GDP Growth Rate",["annual rate","compounded"]],"gdp-007": ["GDP vs. GNP",["gross national product","borders"]],"gdp-008": ["What GDP Misses",["market transactions"]],"sd-001": ["The Law of Demand",["demand curve","downward-sloping"]],"sd-002": ["The Law of Supply",["supply curve","upward-sloping"]],"sd-003": ["Equilibrium Price",["equilibrium"]],"sd-004": ["Price Elasticity",["elastic"]],"sd-005": ["Supply Shocks",["supply shock"]],"sd-006": ["Price Ceilings",["price ceiling","maximum"]],"sd-007": ["Price Floors",["price floor","minimum wage"]],"sd-008": ["Substitutes and Complements",["substitutes","complements"]],"lm-001": ["The Unemployment Rate",["unemployment rate","four weeks"]],"lm-002": ["The Labor Force Participation Rate",["participation rate"]],"lm-003": ["Frictional Unemployment",["frictional","churn"]],"lm-004": ["Structural Unemployment",["structural"]],"lm-005": ["The Phillips Curve",["phillips curve"]],"lm-006": ["The Gig Economy",["contractors","freelancers"]],"lm-007": ["Wage Growth and Inflation",["wage growth","productivity"]],"lm-008": ["The Jobs Report",["household","payroll"]],"tt-001": ["Why Countries Trade",["specializing","opportunity cost"]],"tt-002": ["What is a Tariff?",["tariff","tax on imported"]],"tt-003": ["Trade Deficits",["trade deficit","imported more"]],"tt-004": ["Free Trade Agreements",["free trade agreement","barriers"]],"tt-005": ["The WTO",["world trade organization","disputes"]],"tt-006": ["Protectionism",["protection","domestic industry"]],"tt-007": ["Currency and Trade",["currency","exports"]],"tt-008": ["Supply Chain Reshoring",["resilience","production"]],"hm-001": ["Why Housing is Different",["consumption good","asset"]],"hm-002": ["Mortgage Rates and Affordability",["mortgage payment","rate"]],"hm-003": ["Housing Supply Shortage",["supply","construction"]],"hm-004": ["The 2008 Housing Crash",["credit standards","defaults"]],"hm-005": ["The Lock-In Effect",["lock","fixed-rate"]],"hm-006": ["Rent vs. Own",["renting","owning"]],"hm-007": ["Institutional Investors in Housing",["landlords","institutional"]],"hm-008": ["Housing Starts",["housing starts","leading indicator"]],"cb-001": ["What Does a Central Bank Do?",["lender of last resort","supervises"]],"cb-002": ["Monetary Policy",["monetary policy","credit conditions"]],"cb-003": ["Quantitative Easing (QE)",["longer-term securities","balance sheet"]],"cb-004": ["Central Bank Independence",["independence"]],"cb-005": ["The Lender of Last Resort",["lender of last resort","panic"]],"cb-006": ["The ECB and the Eurozone",["currency union","single policy rate"]],"cb-007": ["Forward Guidance",["forward guidance"]],"cb-008": ["Digital Currencies (CBDCs)",["digital form","settle payments"]],"rec-001": ["What is a Recession?",["nber","decline"]],"rec-002": ["Leading Indicators",["leading indicators"]],"rec-003": ["The Business Cycle",["expansion","trough"]],"rec-004": ["Fiscal Stimulus During Recessions",["spending increases","tax cuts"]],"rec-005": ["Automatic Stabilizers",["automatic","unemployment insurance"]],"rec-006": ["Recessions and Jobs",["lagging indicator","unemployment"]],"rec-007": ["Soft Landing vs. Hard Landing",["soft landing","hard landing"]],"rec-008": ["K-Shaped Recoveries",["diverge","letter k"]],"dd-001": ["Deficit vs. Debt",["deficit","debt"]],"dd-002": ["Debt-to-GDP Ratio",["gross domestic product","denominator"]],"dd-003": ["Who Holds US Debt?",["by the public","trust funds"]],"dd-004": ["The Debt Ceiling",["debt limit","borrowing"]],"dd-005": ["Can Government Debt Be Bad?",["threshold","growth"]],"dd-006": ["Modern Monetary Theory (MMT)",["own currency","default"]],"dd-007": ["Entitlements and Long-Term Debt",["retirement","interest costs"]],"dd-008": ["Interest on the National Debt",["service","rates rise"]]};

const CORE_TOPICS = [
  ['inflation', 'inf'], ['interest-rates', 'ir'], ['gdp', 'gdp'], ['supply-demand', 'sd'],
  ['labor-markets', 'lm'], ['trade-tariffs', 'tt'], ['housing-market', 'hm'], ['central-banks', 'cb'],
  ['recessions', 'rec'], ['debt-deficits', 'dd'], ['exchange-rates', 'fx'], ['consumer-spending', 'cs'],
  ['taxes', 'tax'], ['fiscal-policy', 'fp'], ['economic-indicators', 'ei'],
];
const FREE_TOPICS = ['inflation', 'interest-rates'];

const ISO = /^\d{4}-\d{2}-\d{2}$/;
const YEAR = /\b(1[89]\d{2}|20\d{2})\b/g;
const MAGNITUDE = /(\$\s?\d)|(\d[\d,.]*\s*(percent|trillion|billion|million))/i;
const ANY_QUANTITY = /\d|\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b/i;

class Report {
  constructor() { this.errors = []; this.warnings = []; this.urls = new Map(); }
  fail(where, why) { this.errors.push(`${where}: ${why}`); }
  warn(where, why) { this.warnings.push(`${where}: ${why}`); }
  url(where, url) { if (!this.urls.has(url)) this.urls.set(url, where); }
}

function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function isoDate(s) {
  if (typeof s !== 'string' || !ISO.test(s)) return null;
  const d = new Date(`${s}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function nonEmpty(s) { return typeof s === 'string' && s.trim().length > 0; }

function checkProse(rep, where, text, verificationYear, { named = false, prediction = false } = {}) {
  const lower = text.toLowerCase();
  for (const w of STALE_WORDS) if (lower.includes(w)) rep.fail(where, `uses "${w}", which goes stale`);
  for (const p of ADVICE_PHRASES) if (lower.includes(p)) rep.fail(where, `advice framing: "${p}"`);
  if (named) for (const n of NAMED_ENTITIES) if (lower.includes(n)) rep.fail(where, `names a security/brand/index: "${n.trim()}"`);
  if (prediction) for (const p of PREDICTION_PHRASES) if (lower.includes(p)) rep.fail(where, `prediction framing: "${p}"`);
  for (const m of text.matchAll(YEAR)) {
    const y = Number(m[1]);
    if (y > verificationYear) rep.fail(where, `cites year ${y}, after verification`);
  }
}

function checkSource(rep, where, source, verifiedOn, hosts = APPROVED_HOSTS, floor = verifiedOn) {
  if (!source || typeof source !== 'object') return rep.fail(where, 'missing source block');
  for (const k of ['organization', 'documentTitle', 'url', 'publicationDate', 'datePrecision', 'verificationDate']) {
    if (!nonEmpty(source[k])) rep.fail(where, `source.${k} missing`);
  }
  let url;
  try { url = new URL(source.url); } catch { return rep.fail(where, `unparseable URL ${source.url}`); }
  if (url.protocol !== 'https:') rep.fail(where, 'source URL must be https');
  if (!hosts.has(url.host)) rep.fail(where, `host ${url.host} is not an approved primary source`);
  if (url.search) rep.fail(where, 'source URL must have no query string');
  if (url.hash) rep.fail(where, 'source URL must have no fragment');
  if (!['observed-last-modified', 'stated-on-page', 'observed-on-verification-date'].includes(source.datePrecision)) {
    rep.fail(where, `unknown datePrecision ${source.datePrecision}`);
  }
  const pub = isoDate(source.publicationDate);
  const vd = isoDate(source.verificationDate);
  if (!pub) rep.fail(where, 'publicationDate is not an ISO date');
  if (!vd) rep.fail(where, 'verificationDate is not an ISO date');
  else if (source.verificationDate > verifiedOn || source.verificationDate < floor) {
    rep.fail(where, `verificationDate ${source.verificationDate} must fall between ${floor} and the catalog verifiedOn ${verifiedOn}`);
  }
  if (pub && vd && pub > vd) rep.fail(where, 'publicationDate is after verification');
  rep.url(where, source.url);
}

// Titles across the core and every pack, lowercased → card id, for duplicate warnings.
function titleIndex(excludeCardIDs = new Set()) {
  const index = new Map();
  const add = (card) => { if (!excludeCardIDs.has(card.cardID)) index.set(card.title.trim().toLowerCase(), card.cardID); };
  const core = readJSON(path.join(resources, 'curriculum-v1.1.json'));
  core.topics.forEach(t => t.cards.forEach(add));
  const packsFile = path.join(resources, 'packs-v1.json');
  if (fs.existsSync(packsFile)) readJSON(packsFile).packs.forEach(p => p.topics.forEach(t => t.cards.forEach(add)));
  return index;
}

function checkClaim(rep, cw, card) {
  const prose = `${card.title} ${card.definition} ${card.example}`;
  if (MAGNITUDE.test(prose) && !card.claim) rep.fail(cw, 'states a magnitude but declares no sourced claim');
  if (!card.claim) return;
  const cl = card.claim;
  for (const k of ['units', 'geography', 'claimKind', 'observationPeriod', 'retrievalDate']) if (!nonEmpty(cl[k])) rep.fail(cw, `claim.${k} missing`);
  if (cl.retrievalDate !== card.source?.verificationDate) rep.fail(cw, 'claim.retrievalDate must equal the source verificationDate');
  if (!ANY_QUANTITY.test(card.example ?? '')) rep.fail(cw, 'declares a claim its example never makes');
  if (cl.claimKind === 'observation') {
    if (!/\b(1[89]\d{2}|20\d{2})\b/.test(cl.observationPeriod ?? '')) rep.fail(cw, `observation names no period year: ${cl.observationPeriod}`);
  } else if (cl.claimKind === 'illustration') {
    if (!(cl.units ?? '').toLowerCase().includes('illustrative')) rep.fail(cw, 'illustration units must say "illustrative"');
  } else rep.fail(cw, `unknown claimKind ${cl.claimKind}`);
}

// MARK: - Packs

function validatePacks(file, { fragment = false } = {}) {
  const rep = new Report();
  const core = readJSON(path.join(resources, 'curriculum-v1.1.json'));
  const catalog = readJSON(file);

  if (catalog.schemaVersion !== 1) rep.fail('catalog', `unsupported schemaVersion ${catalog.schemaVersion}`);
  if (catalog.disclaimer !== core.disclaimer) rep.fail('catalog', 'disclaimer differs from the core catalog');
  if (!nonEmpty(catalog.editorialPolicy) || catalog.editorialPolicy.length <= 80) rep.fail('catalog', 'editorialPolicy missing/too short');
  const verifiedOn = catalog.verifiedOn;
  const ver = isoDate(verifiedOn);
  if (!ver) rep.fail('catalog', 'verifiedOn is not an ISO date');
  else if (ver > new Date()) rep.fail('catalog', 'verifiedOn is in the future');
  const verificationYear = ver ? ver.getUTCFullYear() : 0;

  const packs = Array.isArray(catalog.packs) ? catalog.packs : [];
  if (!fragment && packs.length !== EXPECTED_PACKS.length) rep.fail('catalog', `expected ${EXPECTED_PACKS.length} packs, found ${packs.length}`);

  const seenTopics = new Set(core.topics.map(t => t.topicID));
  const seenCards = new Set(core.topics.flatMap(t => t.cards.map(c => c.cardID)));
  const prefixes = new Set(core.topics.flatMap(t => t.cards.map(c => c.cardID.split('-').slice(0, -1).join('-'))));
  const seenProducts = new Set();
  const expectedMap = new Map(EXPECTED_PACKS);
  const titles = titleIndex(new Set(packs.flatMap(p => (p.topics ?? []).flatMap(t => (t.cards ?? []).map(c => c.cardID)))));

  // A fragment must also not collide with the shipped packs it will join.
  if (fragment) {
    const shippedFile = path.join(resources, 'packs-v1.json');
    if (fs.existsSync(shippedFile)) {
      const shipped = readJSON(shippedFile);
      const draftIDs = new Set(packs.map(p => p.packID));
      for (const p of shipped.packs) {
        if (draftIDs.has(p.packID)) continue;
        for (const t of p.topics) {
          seenTopics.add(t.topicID);
          for (const c of t.cards) { seenCards.add(c.cardID); prefixes.add(c.cardID.split('-').slice(0, -1).join('-')); }
        }
      }
    }
  }

  packs.forEach((pack, pi) => {
    const where = `pack ${pack.packID ?? pi}`;
    if (!fragment) {
      const [expID, expProduct] = EXPECTED_PACKS[pi] ?? [];
      if (pack.packID !== expID || pack.productID !== expProduct) rep.fail(where, `unexpected pack ${pack.packID}/${pack.productID} at position ${pi + 1} (expected ${expID}/${expProduct})`);
    } else if (expectedMap.get(pack.packID) !== pack.productID) {
      rep.fail(where, `packID/productID pair not in the 1.1.4 contract: ${pack.packID}/${pack.productID}`);
    }
    if (seenProducts.has(pack.productID)) rep.fail(where, 'duplicate product id'); seenProducts.add(pack.productID);
    if (!nonEmpty(pack.name) || !nonEmpty(pack.icon) || !nonEmpty(pack.summary)) rep.fail(where, 'missing name, icon or summary');
    const topics = Array.isArray(pack.topics) ? pack.topics : [];
    if (topics.length !== 4) rep.fail(where, `carries ${topics.length} topics, expected 4`);
    topics.forEach((topic, ti) => {
      const tw = `${where}/topic ${topic.topicID ?? ti}`;
      for (const k of ['topicID', 'name', 'summary', 'icon']) if (!nonEmpty(topic[k])) rep.fail(tw, `missing ${k}`);
      if (seenTopics.has(topic.topicID)) rep.fail(tw, 'topic id collides with the core catalog or another pack'); seenTopics.add(topic.topicID);
      if (topic.access !== 'pack') rep.fail(tw, `access must be "pack", not ${topic.access}`);
      if (topic.order !== ti + 1) rep.fail(tw, `declares order ${topic.order} at position ${ti + 1}`);
      const cards = Array.isArray(topic.cards) ? topic.cards : [];
      if (cards.length !== PACK_CARDS_PER_TOPIC) rep.fail(tw, `carries ${cards.length} cards, expected ${PACK_CARDS_PER_TOPIC}`);
      if (!cards.some(c => c.difficulty === 'intro')) rep.fail(tw, 'needs at least one intro card');
      let topicPrefix = null;
      cards.forEach((card, ci) => {
        const cw = `${tw}/card ${card.cardID ?? ci}`;
        if (!nonEmpty(card.cardID)) return rep.fail(cw, 'no cardID');
        if (seenCards.has(card.cardID)) rep.fail(cw, 'card id collides with the core catalog or another pack'); seenCards.add(card.cardID);
        const prefix = card.cardID.split('-').slice(0, -1).join('-');
        if (ci === 0) {
          topicPrefix = prefix;
          if (prefixes.has(prefix)) rep.fail(cw, `borrows an existing card prefix "${prefix}"`);
          prefixes.add(prefix);
        } else if (prefix !== topicPrefix) rep.fail(cw, `prefix ${prefix} differs from the topic's ${topicPrefix}`);
        const expectedID = `${prefix}-${String(ci + 1).padStart(3, '0')}`;
        if (card.cardID !== expectedID) rep.fail(cw, `breaks the stable-ID sequence (expected ${expectedID})`);
        if (card.topicID !== topic.topicID) rep.fail(cw, `declares topic ${card.topicID} inside ${topic.topicID}`);
        if (card.supersedes != null || card.supersedesNote != null) rep.fail(cw, 'a new pack card cannot supersede a 1.0 card');
        for (const k of ['title', 'definition', 'example', 'disclaimer']) if (!nonEmpty(card[k])) rep.fail(cw, `missing ${k}`);
        if (card.disclaimer !== CANONICAL_DISCLAIMER) rep.fail(cw, 'disclaimer is not the canonical text');
        if (!['intro', 'intermediate', 'advanced'].includes(card.difficulty)) rep.fail(cw, `unknown difficulty ${card.difficulty}`);
        if ((card.definition ?? '').length < 60) rep.fail(cw, 'definition is too thin (<60 chars)');
        if ((card.example ?? '').length < 40) rep.fail(cw, 'example is too thin (<40 chars)');
        if (card.definition === card.example) rep.fail(cw, 'example equals definition');
        if (card.example && card.definition && card.example.toLowerCase().includes(card.definition.toLowerCase())) rep.fail(cw, 'example merely restates the definition');
        if (!card.editorial || card.editorial.status !== 'verified' || !nonEmpty(card.editorial.reviewer)) rep.fail(cw, 'editorial must be {status: "verified", reviewer: ...}');
        checkSource(rep, cw, card.source, verifiedOn, APPROVED_HOSTS, VERIFICATION_FLOOR.packs);
        const prose = `${card.title} ${card.definition} ${card.example}`;
        checkProse(rep, cw, prose, verificationYear);
        if (!/\d/.test(card.example ?? '')) rep.fail(cw, 'example has no concrete particular (no digit)');
        checkClaim(rep, cw, card);
        const dup = titles.get((card.title ?? '').trim().toLowerCase());
        if (dup && dup !== card.cardID) rep.warn(cw, `title duplicates ${dup}; check the concept is not a duplicate`);
      });
    });
  });
  const total = packs.reduce((n, p) => n + (p.topics ?? []).reduce((m, t) => m + (t.cards ?? []).length, 0), 0);
  const expectedTotal = EXPECTED_PACKS.length * 4 * PACK_CARDS_PER_TOPIC;
  if (!fragment && total !== expectedTotal) rep.fail('catalog', `expected ${expectedTotal} cards, found ${total}`);
  return rep;
}

// MARK: - Courses (schemaVersion 2: story beats, 1.1.5)
//
// docs/content/STORY-SCHEMA-1.1.5.md. A lesson is a list of beats (one idea per
// screen) plus the synthetic charts its beats show. Mirrors CourseCatalog.validate.

export const MAX_BEAT_WORDS = 35;
export const MAX_HEADING_WORDS = 8;
export const BEAT_RANGE = [10, 30];
export const BEAT_KINDS = new Set(['idea', 'term', 'check', 'recap']);
// StoryVisual.allowedSymbols, verbatim (SF Symbols available on iOS 16).
export const ALLOWED_SYMBOLS = new Set([
  'chart.line.uptrend.xyaxis', 'chart.line.downtrend.xyaxis', 'chart.bar.fill', 'chart.pie.fill',
  'percent', 'dollarsign.circle.fill', 'banknote.fill', 'building.columns.fill', 'clock.fill',
  'calendar', 'scalemass.fill', 'arrow.up.arrow.down', 'arrow.triangle.2.circlepath',
  'exclamationmark.triangle.fill', 'lightbulb.fill', 'magnifyingglass', 'person.2.fill',
  'brain.head.profile', 'hourglass', 'shield.fill', 'doc.text.fill', 'eye.fill',
  'questionmark.circle.fill', 'checkmark.seal.fill', 'hand.raised.fill', 'arrow.up.right',
  'arrow.down.right', 'flag.fill', 'tray.full.fill', 'square.stack.3d.up.fill', 'cart.fill',
  'house.fill', 'target', 'ruler.fill', 'speedometer', 'list.number',
]);

export function wordCount(s) {
  return typeof s === 'string' ? s.trim().split(/\s+/).filter(Boolean).length : 0;
}

export function visualWords(v) {
  if (!v || typeof v !== 'object') return 0;
  switch (v.type) {
    case 'stat': return wordCount(v.value) + wordCount(v.label);
    case 'flow': return (Array.isArray(v.steps) ? v.steps : []).reduce((n, x) => n + wordCount(x), 0);
    case 'compare': return ['left', 'right'].reduce((n, k) => n + wordCount(v[k]?.label) + wordCount(v[k]?.detail), 0);
    default: return 0;
  }
}

/** Words the reader reads on the beat's screen (the check's explanation is limited separately). */
export function beatWords(beat) {
  const terms = Array.isArray(beat.terms) ? beat.terms : [];
  const items = Array.isArray(beat.items) ? beat.items : [];
  const choices = Array.isArray(beat.check?.choices) ? beat.check.choices : [];
  return wordCount(beat.heading) + wordCount(beat.text)
    + terms.reduce((n, t) => n + wordCount(t?.term) + wordCount(t?.definition), 0)
    + items.reduce((n, x) => n + wordCount(x), 0)
    + (beat.kind === 'check' ? wordCount(beat.check?.question) + choices.reduce((n, c) => n + wordCount(c), 0) : 0)
    + visualWords(beat.visual);
}

function beatText(beat) {
  const v = beat.visual ?? {};
  return [beat.heading, beat.text,
    ...(beat.terms ?? []).flatMap(t => [t?.term, t?.definition]),
    ...(beat.items ?? []),
    beat.check?.question, ...(beat.check?.choices ?? []), beat.check?.explanation,
    v.value, v.label, ...(v.steps ?? []), v.left?.label, v.left?.detail, v.right?.label, v.right?.detail,
  ].filter(x => typeof x === 'string').join(' ');
}

function checkChart(rep, bw, block, seenCharts) {
  if (!nonEmpty(block.chartID)) rep.fail(bw, 'chart needs a chartID');
  else { if (seenCharts.has(block.chartID)) rep.fail(bw, 'duplicate chartID'); seenCharts.add(block.chartID); }
  if (!['candlestick', 'line', 'bar'].includes(block.kind)) rep.fail(bw, `kind must be candlestick|line|bar, got ${block.kind}`);
  for (const k of ['title', 'caption', 'dataNote', 'xLabel', 'yLabel']) if (!nonEmpty(block[k])) rep.fail(bw, `missing ${k}`);
  if (!/^Synthetic/i.test(block.dataNote ?? '')) rep.fail(bw, 'dataNote must begin with "Synthetic" (no real market data is ever plotted)');
  if (block.kind === 'candlestick') {
    const candles = Array.isArray(block.candles) ? block.candles : [];
    if (candles.length < 8 || candles.length > 60) rep.fail(bw, `candlestick needs 8–60 candles, has ${candles.length}`);
    candles.forEach((c, i) => {
      for (const k of ['x', 'open', 'high', 'low', 'close']) if (typeof c[k] !== 'number') rep.fail(bw, `candle ${i + 1}.${k} must be a number`);
      if (typeof c.high === 'number' && (c.high < Math.max(c.open, c.close) || c.low > Math.min(c.open, c.close))) rep.fail(bw, `candle ${i + 1} OHLC is inconsistent`);
      if (i > 0 && c.x <= candles[i - 1].x) rep.fail(bw, `candle ${i + 1}.x must increase`);
    });
    if (block.series) rep.fail(bw, 'candlestick uses candles, not series');
  } else {
    const series = Array.isArray(block.series) ? block.series : [];
    if (series.length < 1 || series.length > 4) rep.fail(bw, `needs 1–4 series, has ${series.length}`);
    series.forEach((s, si) => {
      if (!nonEmpty(s.name)) rep.fail(bw, `series ${si + 1} needs a name`);
      const pts = Array.isArray(s.points) ? s.points : [];
      if (pts.length < 2 || pts.length > 60) rep.fail(bw, `series ${si + 1} needs 2–60 points, has ${pts.length}`);
      pts.forEach((p, pi) => { if (typeof p.x !== 'number' || typeof p.y !== 'number') rep.fail(bw, `series ${si + 1} point ${pi + 1} must have numeric x and y`); });
    });
    if (block.candles) rep.fail(bw, 'line/bar use series, not candles');
  }
  if (block.markers) {
    if (!Array.isArray(block.markers)) rep.fail(bw, 'markers must be an array');
    else block.markers.forEach((m, i) => { if (typeof m.x !== 'number' || !nonEmpty(m.label)) rep.fail(bw, `marker ${i + 1} needs numeric x and a label`); });
  }
}

function checkVisual(rep, bw, v, chartIDs, usedCharts, usedDiagrams) {
  if (!v || typeof v !== 'object') return rep.fail(bw, 'visual must be an object');
  switch (v.type) {
    case 'diagram':
      if (!ALLOWED_DIAGRAMS.has(v.diagramID)) rep.fail(bw, `diagramID "${v.diagramID}" is not one the app can draw`);
      else usedDiagrams.add(v.diagramID);
      break;
    case 'chart':
      if (!chartIDs.has(v.chartID)) rep.fail(bw, `chartID "${v.chartID}" is not in this lesson's charts`);
      else usedCharts.add(v.chartID);
      break;
    case 'stat':
      if (!nonEmpty(v.value) || v.value.length > 16) rep.fail(bw, 'stat value must be 1–16 characters');
      if (!nonEmpty(v.label) || wordCount(v.label) > 6) rep.fail(bw, 'stat label must be 1–6 words');
      break;
    case 'flow': {
      const steps = Array.isArray(v.steps) ? v.steps : [];
      if (steps.length < 2 || steps.length > 4) rep.fail(bw, `flow needs 2–4 steps, has ${steps.length}`);
      steps.forEach((x, i) => { if (!nonEmpty(x) || wordCount(x) > 4) rep.fail(bw, `flow step ${i + 1} must be 1–4 words`); });
      break;
    }
    case 'compare':
      for (const k of ['left', 'right']) {
        if (!v[k] || !nonEmpty(v[k].label) || wordCount(v[k].label) > 4) rep.fail(bw, `compare ${k}.label must be 1–4 words`);
        if (!v[k] || !nonEmpty(v[k].detail) || wordCount(v[k].detail) > 8) rep.fail(bw, `compare ${k}.detail must be 1–8 words`);
      }
      break;
    case 'symbol':
      if (!ALLOWED_SYMBOLS.has(v.name)) rep.fail(bw, `symbol "${v.name}" is not in the allowlist`);
      break;
    default: rep.fail(bw, `unknown visual type ${v.type}`);
  }
}

function validateCourses(file, { fragment = false } = {}) {
  const rep = new Report();
  const catalog = readJSON(file);
  if (catalog.schemaVersion !== 2) rep.fail('catalog', `unsupported schemaVersion ${catalog.schemaVersion} (story lessons are schemaVersion 2)`);
  if (catalog.disclaimer !== CANONICAL_DISCLAIMER) rep.fail('catalog', 'disclaimer is not the canonical text');
  if (!nonEmpty(catalog.educationalNotice) || !/not (investment|financial) advice/i.test(catalog.educationalNotice)) rep.fail('catalog', 'educationalNotice must say it is not investment advice');
  if (!nonEmpty(catalog.editorialPolicy) || catalog.editorialPolicy.length <= 80) rep.fail('catalog', 'editorialPolicy missing/too short');
  const verifiedOn = catalog.verifiedOn;
  const ver = isoDate(verifiedOn);
  if (!ver) rep.fail('catalog', 'verifiedOn is not an ISO date');
  else if (ver > new Date()) rep.fail('catalog', 'verifiedOn is in the future');
  const verificationYear = ver ? ver.getUTCFullYear() : 0;

  const courses = Array.isArray(catalog.courses) ? catalog.courses : [];
  if (!fragment && courses.length !== EXPECTED_COURSES.length) rep.fail('catalog', `expected ${EXPECTED_COURSES.length} courses, found ${courses.length}`);
  const expected = new Map(EXPECTED_COURSES);
  const seenLessons = new Set(); const seenCharts = new Set(); const seenCourses = new Set();
  const usedDiagrams = new Set();
  const stats = { lessons: 0, beats: 0, checks: 0, maxWords: 0 };

  courses.forEach((course, ci) => {
    const where = `course ${course.courseID ?? ci}`;
    if (!fragment && EXPECTED_COURSES[ci]?.[0] !== course.courseID) rep.fail(where, `unexpected course at position ${ci + 1} (expected ${EXPECTED_COURSES[ci]?.[0]})`);
    const prefix = expected.get(course.courseID);
    if (!prefix) rep.fail(where, 'courseID not in the course contract');
    if (seenCourses.has(course.courseID)) rep.fail(where, 'duplicate courseID'); seenCourses.add(course.courseID);
    for (const k of ['title', 'icon', 'summary', 'level']) if (!nonEmpty(course[k])) rep.fail(where, `missing ${k}`);
    if (!['intro', 'intermediate'].includes(course.level)) rep.fail(where, `level must be intro|intermediate, got ${course.level}`);
    if (!(Number.isInteger(course.estimatedMinutes) && course.estimatedMinutes > 0)) rep.fail(where, 'estimatedMinutes must be a positive integer');
    checkProse(rep, where, `${course.title} ${course.summary}`, verificationYear, { named: true, prediction: true });
    const lessons = Array.isArray(course.lessons) ? course.lessons : [];
    if (lessons.length < 5) rep.fail(where, `has ${lessons.length} lessons, need at least 5`);
    if (!fragment && lessons.length !== LESSONS_PER_COURSE) rep.fail(where, `has ${lessons.length} lessons, expected ${LESSONS_PER_COURSE}`);
    const minutes = lessons.reduce((n, l) => n + (l.estimatedMinutes ?? 0), 0);
    if (course.estimatedMinutes !== minutes) rep.fail(where, `estimatedMinutes ${course.estimatedMinutes} is not the sum of its lessons (${minutes})`);
    lessons.forEach((lesson, li) => {
      const lw = `${where}/lesson ${lesson.lessonID ?? li}`;
      stats.lessons += 1;
      const expectedID = `${prefix}-${String(li + 1).padStart(2, '0')}`;
      if (lesson.lessonID !== expectedID) rep.fail(lw, `lessonID must be ${expectedID}`);
      if (seenLessons.has(lesson.lessonID)) rep.fail(lw, 'duplicate lessonID'); seenLessons.add(lesson.lessonID);
      for (const k of ['title', 'summary']) if (!nonEmpty(lesson[k])) rep.fail(lw, `missing ${k}`);
      if (wordCount(lesson.summary) > MAX_BEAT_WORDS) rep.fail(lw, `summary is ${wordCount(lesson.summary)} words (the cover allows ${MAX_BEAT_WORDS})`);
      if (!(Number.isInteger(lesson.estimatedMinutes) && lesson.estimatedMinutes > 0)) rep.fail(lw, 'estimatedMinutes must be a positive integer');
      if (typeof lesson.isPreview !== 'boolean') rep.fail(lw, 'isPreview must be a boolean');
      else if (lesson.isPreview !== (li === 0)) rep.fail(lw, 'exactly the first lesson of each course is the free preview');
      if ('blocks' in lesson) rep.fail(lw, 'a story lesson must not carry 1.1.4 blocks');
      checkProse(rep, lw, `${lesson.title} ${lesson.summary}`, verificationYear, { named: true, prediction: true });

      const charts = Array.isArray(lesson.charts) ? lesson.charts : [];
      const chartIDs = new Set();
      charts.forEach((chart, i) => {
        const cw = `${lw}/chart ${chart.chartID ?? i + 1}`;
        checkChart(rep, cw, chart, seenCharts);
        if (nonEmpty(chart.chartID)) chartIDs.add(chart.chartID);
        checkProse(rep, cw, `${chart.title ?? ''} ${chart.caption ?? ''} ${chart.dataNote ?? ''}`, verificationYear, { named: true, prediction: true });
      });

      const beats = Array.isArray(lesson.beats) ? lesson.beats : [];
      stats.beats += beats.length;
      if (beats.length < BEAT_RANGE[0] || beats.length > BEAT_RANGE[1]) rep.fail(lw, `has ${beats.length} beats, needs ${BEAT_RANGE[0]}–${BEAT_RANGE[1]}`);
      const usedCharts = new Set();
      let checks = 0, recaps = 0, visuals = 0, symbols = 0;
      beats.forEach((beat, bi) => {
        const bw = `${lw}/beat ${bi + 1} (${beat.kind})`;
        if (!BEAT_KINDS.has(beat.kind)) rep.fail(bw, `unknown beat kind ${beat.kind}`);
        const words = beatWords(beat);
        stats.maxWords = Math.max(stats.maxWords, words);
        if (words > MAX_BEAT_WORDS) rep.fail(bw, `${words} words on one screen (max ${MAX_BEAT_WORDS})`);
        if (beat.heading !== undefined && (!nonEmpty(beat.heading) || wordCount(beat.heading) > MAX_HEADING_WORDS)) rep.fail(bw, `heading must be 1–${MAX_HEADING_WORDS} words`);
        if (beat.tone !== undefined && (beat.kind !== 'idea' || !['note', 'caution', 'example'].includes(beat.tone))) rep.fail(bw, 'tone is note|caution|example, on idea beats only');
        const has = k => beat[k] !== undefined;
        switch (beat.kind) {
          case 'idea':
            if (!nonEmpty(beat.text)) rep.fail(bw, 'an idea beat needs text');
            if (has('terms') || has('check') || has('items')) rep.fail(bw, 'an idea beat carries only heading, text, tone and visual');
            break;
          case 'term': {
            const terms = Array.isArray(beat.terms) ? beat.terms : [];
            if (terms.length < 1 || terms.length > 2) rep.fail(bw, `a term beat needs 1–2 terms, has ${terms.length}`);
            terms.forEach((t, i) => { if (!nonEmpty(t?.term) || !nonEmpty(t?.definition)) rep.fail(bw, `term ${i + 1} needs a term and a definition`); });
            if (has('check') || has('items')) rep.fail(bw, 'a term beat carries no check or items');
            break;
          }
          case 'check': {
            checks += 1;
            const q = beat.check ?? {};
            const choices = Array.isArray(q.choices) ? q.choices : [];
            if (!nonEmpty(q.question)) rep.fail(bw, 'check needs a question');
            if (choices.length < 3 || choices.length > 4) rep.fail(bw, `check needs 3–4 choices, has ${choices.length}`);
            if (choices.some(c => !nonEmpty(c))) rep.fail(bw, 'empty choice');
            if (new Set(choices).size !== choices.length) rep.fail(bw, 'duplicate choices');
            if (!(Number.isInteger(q.answerIndex) && q.answerIndex >= 0 && q.answerIndex < choices.length)) rep.fail(bw, 'answerIndex out of range');
            if (!nonEmpty(q.explanation)) rep.fail(bw, 'check needs an explanation');
            else if (wordCount(q.explanation) > MAX_BEAT_WORDS) rep.fail(bw, `explanation is ${wordCount(q.explanation)} words (max ${MAX_BEAT_WORDS})`);
            if (bi === 0 || bi === beats.length - 1) rep.fail(bw, 'a check is never the first or last beat');
            if (has('text') || has('terms') || has('items')) rep.fail(bw, 'a check beat carries only its check and a visual');
            break;
          }
          case 'recap': {
            recaps += 1;
            const items = Array.isArray(beat.items) ? beat.items : [];
            if (items.length < 2 || items.length > 5) rep.fail(bw, `recap needs 2–5 items, has ${items.length}`);
            if (items.some(x => !nonEmpty(x))) rep.fail(bw, 'empty recap item');
            if (bi !== beats.length - 1) rep.fail(bw, 'the recap is the last beat');
            if (has('visual') || has('text') || has('terms') || has('check')) rep.fail(bw, 'a recap beat carries only items (and an optional heading)');
            break;
          }
          default: break;
        }
        if (beat.visual !== undefined) {
          visuals += 1;
          if (beat.visual?.type === 'symbol') symbols += 1;
          checkVisual(rep, bw, beat.visual, chartIDs, usedCharts, usedDiagrams);
        }
        checkProse(rep, bw, beatText(beat), verificationYear, { named: true, prediction: true });
      });
      stats.checks += checks;
      if (beats.length && !['idea', 'term'].includes(beats[0].kind)) rep.fail(lw, 'the first beat is an idea or a term');
      if (recaps !== 1) rep.fail(lw, `needs exactly one recap, has ${recaps}`);
      if (checks < 1 || checks > 2) rep.fail(lw, `needs 1–2 checks, has ${checks}`);
      if (visuals * 2 <= beats.length) rep.fail(lw, `only ${visuals} of ${beats.length} beats carry a visual (needs more than half)`);
      if (symbols > Math.floor(visuals / 3)) rep.fail(lw, `${symbols} symbol visuals; at most a third of the ${visuals} visual beats may be symbols`);
      for (const id of chartIDs) if (!usedCharts.has(id)) rep.fail(lw, `chart ${id} is never shown by a beat`);
      const sources = Array.isArray(lesson.sources) ? lesson.sources : [];
      if (sources.length < 1) rep.fail(lw, 'needs at least one primary source');
      sources.forEach((s, si) => checkSource(rep, `${lw}/source ${si + 1}`, s, verifiedOn, COURSE_HOSTS, VERIFICATION_FLOOR.courses));
    });
  });
  if (!fragment) for (const d of ALLOWED_DIAGRAMS) if (!usedDiagrams.has(d)) rep.fail('catalog', `diagram ${d} is not used by any lesson`);
  rep.stats = stats;
  return rep;
}

// MARK: - Daily brief

function validateBrief(file) {
  const rep = new Report();
  const brief = readJSON(file);
  const where = 'brief';
  if (brief.schemaVersion !== 1) rep.fail(where, `unsupported schemaVersion ${brief.schemaVersion}`);
  if (!isoDate(brief.briefDate)) rep.fail(where, 'briefDate must be YYYY-MM-DD');
  if (!nonEmpty(brief.publishedAt) || Number.isNaN(new Date(brief.publishedAt).getTime())) rep.fail(where, 'publishedAt must be an ISO-8601 timestamp');
  if (!nonEmpty(brief.headline)) rep.fail(where, 'headline missing');
  if (!nonEmpty(brief.disclaimer) || !/not (investment|financial) advice/i.test(brief.disclaimer)) rep.fail(where, 'disclaimer must say it is not investment advice');
  if (!nonEmpty(brief.methodology) || !/primary/i.test(brief.methodology)) rep.fail(where, 'methodology must describe the primary-source-only method');
  if (brief.isSample !== undefined && typeof brief.isSample !== 'boolean') rep.fail(where, 'isSample must be a boolean');
  const year = isoDate(brief.briefDate)?.getUTCFullYear() ?? 0;
  const sections = Array.isArray(brief.sections) ? brief.sections : [];
  const types = sections.map(s => s.type);
  for (const t of ['released', 'scheduled', 'concept']) if (!types.includes(t)) rep.fail(where, `missing "${t}" section`);
  sections.forEach((s, si) => {
    const sw = `${where}/section ${si + 1} (${s.type})`;
    if (!nonEmpty(s.title)) rep.fail(sw, 'missing title');
    const items = Array.isArray(s.items) ? s.items : [];
    if (s.type === 'released') {
      if (items.length < 1) rep.fail(sw, 'needs at least one released item');
      items.forEach((it, ii) => {
        const iw = `${sw}/item ${ii + 1}`;
        for (const k of ['title', 'summary', 'releaseDate']) if (!nonEmpty(it[k])) rep.fail(iw, `missing ${k}`);
        if (!isoDate(it.releaseDate)) rep.fail(iw, 'releaseDate must be YYYY-MM-DD');
        const figs = Array.isArray(it.figures) ? it.figures : [];
        if (figs.length < 1) rep.fail(iw, 'needs at least one figure');
        figs.forEach((f, fi) => { if (!nonEmpty(f.label) || !nonEmpty(f.value)) rep.fail(iw, `figure ${fi + 1} needs label and value`); });
        if (!it.source) rep.fail(iw, 'missing source');
        else {
          for (const k of ['organization', 'documentTitle', 'url', 'retrievedAt']) if (!nonEmpty(it.source[k])) rep.fail(iw, `source.${k} missing`);
          try {
            const u = new URL(it.source.url);
            if (u.protocol !== 'https:') rep.fail(iw, 'source must be https');
            if (!BRIEF_HOSTS.has(u.host)) rep.fail(iw, `host ${u.host} is not an allowed brief source (official releases and open-licence statistical offices only)`);
            rep.url(iw, it.source.url);
          } catch { rep.fail(iw, `unparseable source URL ${it.source.url}`); }
        }
        checkProse(rep, iw, `${it.title} ${it.summary} ${it.meaning ?? ''}`, year, { named: true, prediction: true });
      });
    } else if (s.type === 'scheduled') {
      if (items.length < 1) rep.fail(sw, 'needs at least one scheduled item');
      items.forEach((it, ii) => {
        const iw = `${sw}/item ${ii + 1}`;
        for (const k of ['date', 'title', 'organization', 'url']) if (!nonEmpty(it[k])) rep.fail(iw, `missing ${k}`);
        if (!isoDate(it.date)) rep.fail(iw, 'date must be YYYY-MM-DD');
        try { const u = new URL(it.url); if (!BRIEF_HOSTS.has(u.host)) rep.fail(iw, `host ${u.host} not allowed`); rep.url(iw, it.url); } catch { rep.fail(iw, 'unparseable url'); }
        checkProse(rep, iw, it.title, year, { named: true, prediction: true });
      });
    } else if (s.type === 'concept') {
      for (const k of ['conceptTitle', 'text']) if (!nonEmpty(s[k])) rep.fail(sw, `missing ${k}`);
      if (!nonEmpty(s.linkedCardID) && !nonEmpty(s.linkedLessonID)) rep.fail(sw, 'concept must link a card or a lesson');
      checkProse(rep, sw, `${s.conceptTitle} ${s.text}`, year, { named: true, prediction: true });
    } else rep.fail(sw, `unknown section type ${s.type}`);
  });
  return rep;
}

// MARK: - Core curriculum

function validateCurriculum(file, { fragment = false } = {}) {
  const rep = new Report();
  const catalog = readJSON(file);
  if (catalog.schemaVersion !== 1) rep.fail('catalog', `unsupported schemaVersion ${catalog.schemaVersion}`);
  if (catalog.catalogVersion !== '1.1') rep.fail('catalog', `catalogVersion must stay "1.1", got ${catalog.catalogVersion}`);
  if (catalog.disclaimer !== CANONICAL_DISCLAIMER) rep.fail('catalog', 'disclaimer is not the canonical text');
  if (!nonEmpty(catalog.editorialPolicy) || catalog.editorialPolicy.length <= 80) rep.fail('catalog', 'editorialPolicy missing/too short');
  const verifiedOn = catalog.verifiedOn;
  const ver = isoDate(verifiedOn);
  if (!ver) rep.fail('catalog', 'verifiedOn is not an ISO date');
  else if (ver > new Date()) rep.fail('catalog', 'verifiedOn is in the future');
  const verificationYear = ver ? ver.getUTCFullYear() : 0;

  const topics = Array.isArray(catalog.topics) ? catalog.topics : [];
  if (topics.length !== CORE_TOPICS.length) rep.fail('catalog', `expected ${CORE_TOPICS.length} topics, found ${topics.length}`);
  const allowedCounts = fragment ? [8, CORE_CARDS_PER_TOPIC] : [CORE_CARDS_PER_TOPIC];
  const seenCards = new Set();
  const byID = new Map();
  const titles = titleIndex(new Set(topics.flatMap(t => (t.cards ?? []).map(c => c.cardID))));

  topics.forEach((topic, ti) => {
    const [expID, prefix] = CORE_TOPICS[ti] ?? [];
    const tw = `topic ${topic.topicID ?? ti}`;
    if (topic.topicID !== expID) rep.fail(tw, `unexpected topic at position ${ti + 1} (expected ${expID})`);
    if (topic.order !== ti + 1) rep.fail(tw, `declares order ${topic.order} at position ${ti + 1}`);
    for (const k of ['topicID', 'name', 'summary', 'icon']) if (!nonEmpty(topic[k])) rep.fail(tw, `missing ${k}`);
    const expectedAccess = FREE_TOPICS.includes(topic.topicID) ? 'free' : 'paid';
    if (topic.access !== expectedAccess) rep.fail(tw, `access must stay "${expectedAccess}", got ${topic.access}`);
    const cards = Array.isArray(topic.cards) ? topic.cards : [];
    if (!allowedCounts.includes(cards.length)) rep.fail(tw, `carries ${cards.length} cards, expected ${allowedCounts.join(' or ')}`);
    if (!cards.some(c => c.difficulty === 'intro')) rep.fail(tw, 'needs at least one intro card');
    cards.forEach((card, ci) => {
      const cw = `${tw}/card ${card.cardID ?? ci}`;
      if (!nonEmpty(card.cardID)) return rep.fail(cw, 'no cardID');
      const expectedID = `${prefix}-${String(ci + 1).padStart(3, '0')}`;
      if (card.cardID !== expectedID) rep.fail(cw, `breaks the stable-ID sequence (expected ${expectedID})`);
      if (seenCards.has(card.cardID)) rep.fail(cw, 'duplicate card id'); seenCards.add(card.cardID);
      byID.set(card.cardID, card);
      if (card.topicID !== topic.topicID) rep.fail(cw, `declares topic ${card.topicID} inside ${topic.topicID}`);
      if (LEGACY_PINS[card.cardID]) {
        if (card.supersedes !== `econbyte-1.0:${card.cardID}`) rep.fail(cw, 'a 1.0 card must declare supersedes econbyte-1.0:<id>');
      } else if (card.supersedes != null || card.supersedesNote != null) rep.fail(cw, 'a card new since 1.0 supersedes nothing');
      for (const k of ['title', 'definition', 'example', 'disclaimer']) if (!nonEmpty(card[k])) rep.fail(cw, `missing ${k}`);
      if (card.disclaimer !== CANONICAL_DISCLAIMER) rep.fail(cw, 'disclaimer is not the canonical text');
      if (!['intro', 'intermediate', 'advanced'].includes(card.difficulty)) rep.fail(cw, `unknown difficulty ${card.difficulty}`);
      if ((card.definition ?? '').length < 60) rep.fail(cw, 'definition is too thin (<60 chars)');
      if ((card.example ?? '').length < 40) rep.fail(cw, 'example is too thin (<40 chars)');
      if (card.example && card.definition && card.example.toLowerCase().includes(card.definition.toLowerCase())) rep.fail(cw, 'example merely restates the definition');
      if (!card.editorial || card.editorial.status !== 'verified' || !nonEmpty(card.editorial.reviewer)) rep.fail(cw, 'editorial must be {status: "verified", reviewer: ...}');
      checkSource(rep, cw, card.source, verifiedOn, CORE_HOSTS, VERIFICATION_FLOOR.curriculum);
      checkProse(rep, cw, `${card.title} ${card.definition} ${card.example}`, verificationYear);
      if (!/\d/.test(card.example ?? '')) rep.fail(cw, 'example has no concrete particular (no digit)');
      checkClaim(rep, cw, card);
      const dup = titles.get((card.title ?? '').trim().toLowerCase());
      if (dup && dup !== card.cardID) rep.warn(cw, `title duplicates ${dup}; check the concept is not a duplicate`);
    });
  });

  // Legacy concept pins: every 1.0 id still teaches its concept (or declares the
  // change), and no other card's title + definition satisfies another id's pin.
  const prose = new Map([...byID].map(([id, c]) => [id, `${c.title} ${c.definition}`.toLowerCase()]));
  for (const [id, [concept, tokens]] of Object.entries(LEGACY_PINS)) {
    const card = byID.get(id);
    if (!card) { rep.fail(`pin ${id}`, 'shipped 1.0 card id is missing'); continue; }
    if (!tokens.every(t => prose.get(id).includes(t)) && !nonEmpty(card.supersedesNote)) rep.fail(`pin ${id}`, `no longer teaches "${concept}" and has no supersedesNote`);
    for (const [other, text] of prose) {
      if (other !== id && tokens.every(t => text.includes(t))) rep.fail(`card ${other}`, `title + definition satisfy ${id}'s legacy pin ${JSON.stringify(tokens)}; reword so the pin still identifies one card`);
    }
  }
  if (!fragment && seenCards.size !== CORE_TOPICS.length * CORE_CARDS_PER_TOPIC) rep.fail('catalog', `expected ${CORE_TOPICS.length * CORE_CARDS_PER_TOPIC} cards, found ${seenCards.size}`);
  return rep;
}

// MARK: - Network

async function resolve(rep) {
  const results = [];
  for (const [url, where] of rep.urls) {
    try {
      // Some publishers (ftc.gov) answer a burst of sequential requests with a
      // transient 429/5xx; retry those a few times, spaced out, before reporting.
      let res;
      for (let attempt = 0; attempt < 4; attempt++) {
        if (attempt) await new Promise(r => setTimeout(r, 4000 * attempt));
        res = await fetch(url, {
          redirect: 'follow',
          headers: { 'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15', accept: 'text/html,*/*' },
          signal: AbortSignal.timeout(20000),
        });
        if (!(res.status === 429 || res.status >= 500)) break;
      }
      if (res.status === 200) results.push(['OK', url]);
      else if (res.status === 403 || res.status === 429) results.push(['UNVERIFIABLE', `${url} (HTTP ${res.status} from this box — verify by another client)`]);
      else results.push(['FAIL', `${url} → HTTP ${res.status} (cited by ${where})`]);
    } catch (e) {
      results.push(['UNVERIFIABLE', `${url} (${e.name}: ${e.message})`]);
    }
  }
  return results;
}

async function main() {
  const [kind, file, ...flags] = process.argv.slice(2);
  if (!kind || !file) {
    console.error('usage: validate_content.mjs packs|courses|brief|curriculum <file> [--fragment] [--net]');
    process.exit(2);
  }
  const fragment = flags.includes('--fragment');
  const net = flags.includes('--net');
  let rep;
  if (kind === 'packs') rep = validatePacks(file, { fragment });
  else if (kind === 'courses') rep = validateCourses(file, { fragment });
  else if (kind === 'brief') rep = validateBrief(file);
  else if (kind === 'curriculum') rep = validateCurriculum(file, { fragment });
  else { console.error(`unknown kind ${kind}`); process.exit(2); }

  for (const w of rep.warnings) console.log(`WARN  ${w}`);
  for (const e of rep.errors) console.log(`FAIL  ${e}`);
  if (rep.stats) console.log(`stats: ${JSON.stringify(rep.stats)}`);
  console.log(`${rep.errors.length} error(s), ${rep.warnings.length} warning(s), ${rep.urls.size} distinct URL(s) cited`);
  let netFailures = 0;
  if (net) {
    const results = await resolve(rep);
    for (const [status, line] of results) console.log(`${status.padEnd(12)} ${line}`);
    netFailures = results.filter(r => r[0] === 'FAIL').length;
    console.log(`network: ${results.filter(r => r[0] === 'OK').length} ok, ${netFailures} failed, ${results.filter(r => r[0] === 'UNVERIFIABLE').length} unverifiable`);
  }
  process.exit(rep.errors.length || netFailures ? 1 : 0);
}

// Run as a CLI only when executed directly (the build script imports the helpers).
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main();
