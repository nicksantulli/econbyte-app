#!/usr/bin/env node
// EconByte content validator (1.1.4).
//
// A Node mirror of the Swift acceptance gates so content can be checked
// without an xcodebuild run (one xcodebuild at a time on the build Mac):
//
//   node scripts/validate_content.mjs packs   <file> [--fragment] [--net]
//   node scripts/validate_content.mjs courses <file> [--fragment] [--net]
//   node scripts/validate_content.mjs brief   <file> [--net]
//
// `packs` mirrors PackCatalog.validate + PackCatalogTests (structure, id
// collisions with the core catalog and other packs, approved hosts, dates,
// stale/advice wording, declared claims). `courses` mirrors CourseCatalog.validate
// + CourseCatalogTests. `brief` mirrors DailyBrief.validate. `--fragment`
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
  // with open reuse terms, the Fed's own education site, and archives.gov.
  'www.bankofengland.co.uk', 'ec.europa.eu', 'www.ons.gov.uk',
  'www150.statcan.gc.ca', 'www.statcan.gc.ca', 'www.federalreserveeducation.org',
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

function checkSource(rep, where, source, verifiedOn, hosts = APPROVED_HOSTS) {
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
  const ver = isoDate(verifiedOn);
  if (!pub) rep.fail(where, 'publicationDate is not an ISO date');
  if (source.verificationDate !== verifiedOn) rep.fail(where, `verificationDate must equal catalog verifiedOn (${verifiedOn})`);
  if (pub && ver && pub > ver) rep.fail(where, 'publicationDate is after verification');
  rep.url(where, source.url);
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
      if (cards.length !== 8) rep.fail(tw, `carries ${cards.length} cards, expected 8`);
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
        checkSource(rep, cw, card.source, verifiedOn);
        const prose = `${card.title} ${card.definition} ${card.example}`;
        checkProse(rep, cw, prose, verificationYear);
        if (!/\d/.test(card.example ?? '')) rep.fail(cw, 'example has no concrete particular (no digit)');
        if (MAGNITUDE.test(prose) && !card.claim) rep.fail(cw, 'states a magnitude but declares no sourced claim');
        if (card.claim) {
          const cl = card.claim;
          for (const k of ['units', 'geography', 'claimKind', 'observationPeriod', 'retrievalDate']) if (!nonEmpty(cl[k])) rep.fail(cw, `claim.${k} missing`);
          if (cl.retrievalDate !== verifiedOn) rep.fail(cw, 'claim.retrievalDate must equal verifiedOn');
          if (!ANY_QUANTITY.test(card.example ?? '')) rep.fail(cw, 'declares a claim its example never makes');
          if (cl.claimKind === 'observation') {
            if (!/\b(1[89]\d{2}|20\d{2})\b/.test(cl.observationPeriod ?? '')) rep.fail(cw, `observation names no period year: ${cl.observationPeriod}`);
          } else if (cl.claimKind === 'illustration') {
            if (!(cl.units ?? '').toLowerCase().includes('illustrative')) rep.fail(cw, 'illustration units must say "illustrative"');
          } else rep.fail(cw, `unknown claimKind ${cl.claimKind}`);
        }
      });
    });
  });
  const total = packs.reduce((n, p) => n + (p.topics ?? []).reduce((m, t) => m + (t.cards ?? []).length, 0), 0);
  if (!fragment && total !== EXPECTED_PACKS.length * 32) rep.fail('catalog', `expected ${EXPECTED_PACKS.length * 32} cards, found ${total}`);
  return rep;
}

// MARK: - Courses

function textOf(block) {
  switch (block.type) {
    case 'paragraph': return block.text ?? '';
    case 'callout': return `${block.title ?? ''} ${block.text ?? ''}`;
    case 'keyTerms': return (block.terms ?? []).map(t => `${t.term} ${t.definition}`).join(' ');
    case 'diagram': return block.caption ?? '';
    case 'chart': return `${block.title ?? ''} ${block.caption ?? ''} ${block.dataNote ?? ''}`;
    case 'quiz': return `${block.question ?? ''} ${(block.choices ?? []).join(' ')} ${block.explanation ?? ''}`;
    case 'takeaways': return (block.items ?? []).join(' ');
    default: return '';
  }
}

function validateCourses(file, { fragment = false } = {}) {
  const rep = new Report();
  const catalog = readJSON(file);
  if (catalog.schemaVersion !== 1) rep.fail('catalog', `unsupported schemaVersion ${catalog.schemaVersion}`);
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

  courses.forEach((course, ci) => {
    const where = `course ${course.courseID ?? ci}`;
    if (!fragment && EXPECTED_COURSES[ci]?.[0] !== course.courseID) rep.fail(where, `unexpected course at position ${ci + 1} (expected ${EXPECTED_COURSES[ci]?.[0]})`);
    const prefix = expected.get(course.courseID);
    if (!prefix) rep.fail(where, 'courseID not in the 1.1.4 contract');
    if (seenCourses.has(course.courseID)) rep.fail(where, 'duplicate courseID'); seenCourses.add(course.courseID);
    for (const k of ['title', 'icon', 'summary', 'level']) if (!nonEmpty(course[k])) rep.fail(where, `missing ${k}`);
    if (!['intro', 'intermediate'].includes(course.level)) rep.fail(where, `level must be intro|intermediate, got ${course.level}`);
    if (!(Number.isInteger(course.estimatedMinutes) && course.estimatedMinutes > 0)) rep.fail(where, 'estimatedMinutes must be a positive integer');
    checkProse(rep, where, `${course.title} ${course.summary}`, verificationYear, { named: true, prediction: true });
    const lessons = Array.isArray(course.lessons) ? course.lessons : [];
    if (lessons.length < 5) rep.fail(where, `has ${lessons.length} lessons, need at least 5`);
    lessons.forEach((lesson, li) => {
      const lw = `${where}/lesson ${lesson.lessonID ?? li}`;
      const expectedID = `${prefix}-${String(li + 1).padStart(2, '0')}`;
      if (lesson.lessonID !== expectedID) rep.fail(lw, `lessonID must be ${expectedID}`);
      if (seenLessons.has(lesson.lessonID)) rep.fail(lw, 'duplicate lessonID'); seenLessons.add(lesson.lessonID);
      for (const k of ['title', 'summary']) if (!nonEmpty(lesson[k])) rep.fail(lw, `missing ${k}`);
      if (!(Number.isInteger(lesson.estimatedMinutes) && lesson.estimatedMinutes > 0)) rep.fail(lw, 'estimatedMinutes must be a positive integer');
      if (typeof lesson.isPreview !== 'boolean') rep.fail(lw, 'isPreview must be a boolean');
      else if (lesson.isPreview !== (li === 0)) rep.fail(lw, 'exactly the first lesson of each course is the free preview');
      const blocks = Array.isArray(lesson.blocks) ? lesson.blocks : [];
      if (blocks.length < 5) rep.fail(lw, `has ${blocks.length} blocks, need at least 5`);
      const counts = {};
      let prose = 0;
      blocks.forEach((block, bi) => {
        const bw = `${lw}/block ${bi + 1} (${block.type})`;
        counts[block.type] = (counts[block.type] ?? 0) + 1;
        switch (block.type) {
          case 'paragraph':
            if (!nonEmpty(block.text) || block.text.length < 80) rep.fail(bw, 'paragraph text < 80 chars');
            prose += (block.text ?? '').length;
            break;
          case 'callout':
            if (!['note', 'caution', 'example'].includes(block.style)) rep.fail(bw, `style must be note|caution|example, got ${block.style}`);
            if (!nonEmpty(block.title) || !nonEmpty(block.text)) rep.fail(bw, 'callout needs title and text');
            prose += (block.text ?? '').length;
            break;
          case 'keyTerms': {
            const terms = Array.isArray(block.terms) ? block.terms : [];
            if (terms.length < 2 || terms.length > 6) rep.fail(bw, `keyTerms needs 2–6 terms, has ${terms.length}`);
            terms.forEach((t, i) => { if (!nonEmpty(t.term) || !nonEmpty(t.definition) || t.definition.length < 30) rep.fail(bw, `term ${i + 1} needs a term and a definition ≥ 30 chars`); });
            break;
          }
          case 'diagram':
            if (!ALLOWED_DIAGRAMS.has(block.diagramID)) rep.fail(bw, `diagramID "${block.diagramID}" is not one the app can draw (${[...ALLOWED_DIAGRAMS].join(', ')})`);
            if (!nonEmpty(block.caption)) rep.fail(bw, 'diagram needs a caption');
            break;
          case 'chart': {
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
            break;
          }
          case 'quiz': {
            if (!nonEmpty(block.question)) rep.fail(bw, 'quiz needs a question');
            const choices = Array.isArray(block.choices) ? block.choices : [];
            if (choices.length < 3 || choices.length > 4) rep.fail(bw, `quiz needs 3–4 choices, has ${choices.length}`);
            if (!(Number.isInteger(block.answerIndex) && block.answerIndex >= 0 && block.answerIndex < choices.length)) rep.fail(bw, 'answerIndex out of range');
            if (!nonEmpty(block.explanation) || block.explanation.length < 40) rep.fail(bw, 'explanation < 40 chars');
            if (new Set(choices).size !== choices.length) rep.fail(bw, 'duplicate choices');
            break;
          }
          case 'takeaways': {
            const items = Array.isArray(block.items) ? block.items : [];
            if (items.length < 2 || items.length > 5) rep.fail(bw, `takeaways needs 2–5 items, has ${items.length}`);
            break;
          }
          default: rep.fail(bw, `unknown block type ${block.type}`);
        }
        checkProse(rep, bw, textOf(block), verificationYear, { named: true, prediction: true });
      });
      if ((counts.chart ?? 0) + (counts.diagram ?? 0) < 1) rep.fail(lw, 'needs at least one chart or diagram');
      if ((counts.quiz ?? 0) !== 1) rep.fail(lw, `needs exactly one quiz, has ${counts.quiz ?? 0}`);
      if ((counts.paragraph ?? 0) < 1) rep.fail(lw, 'needs at least one paragraph');
      if ((counts.takeaways ?? 0) < 1) rep.fail(lw, 'needs a takeaways block');
      if (blocks.length && blocks[blocks.length - 1].type !== 'takeaways') rep.fail(lw, 'the last block must be takeaways');
      if (prose < 600) rep.fail(lw, `prose (paragraph + callout text) is ${prose} chars, need ≥ 600`);
      if (prose > 6000) rep.warn(lw, `prose is ${prose} chars — long for a phone lesson`);
      const sources = Array.isArray(lesson.sources) ? lesson.sources : [];
      if (sources.length < 1) rep.fail(lw, 'needs at least one primary source');
      sources.forEach((s, si) => checkSource(rep, `${lw}/source ${si + 1}`, s, verifiedOn));
    });
  });
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

// MARK: - Network

async function resolve(rep) {
  const results = [];
  for (const [url, where] of rep.urls) {
    try {
      const res = await fetch(url, {
        redirect: 'follow',
        headers: { 'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15', accept: 'text/html,*/*' },
        signal: AbortSignal.timeout(20000),
      });
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
    console.error('usage: validate_content.mjs packs|courses|brief <file> [--fragment] [--net]');
    process.exit(2);
  }
  const fragment = flags.includes('--fragment');
  const net = flags.includes('--net');
  let rep;
  if (kind === 'packs') rep = validatePacks(file, { fragment });
  else if (kind === 'courses') rep = validateCourses(file, { fragment });
  else if (kind === 'brief') rep = validateBrief(file);
  else { console.error(`unknown kind ${kind}`); process.exit(2); }

  for (const w of rep.warnings) console.log(`WARN  ${w}`);
  for (const e of rep.errors) console.log(`FAIL  ${e}`);
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

main();
