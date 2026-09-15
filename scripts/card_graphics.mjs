#!/usr/bin/env node
// EconByte 1.1.5 card graphics: checker, resolver and merger.
//
// Contract: docs/content/CARD-GRAPHICS-1.1.5.md. The Swift gate is
// EconByteTests/CardGraphicsTests.swift; this file is the content checker that
// compares every number in a graphic with the card's own prose, re-resolves
// real-data recipes and recomputes formula series.
//
//   node scripts/card_graphics.mjs check [--require-all] [--net] [--quiet]
//   node scripts/card_graphics.mjs check-fragment <file> [--net]
//   node scripts/card_graphics.mjs resolve-fragment <file>
//   node scripts/card_graphics.mjs merge <file>...
//   node scripts/card_graphics.mjs stats
//   node scripts/card_graphics.mjs dump [cardID...]
//
// Recipe data is cached under $CARD_GRAPHICS_CACHE (default: $TMPDIR/econbyte-card-graphics-cache).
// `check` recomputes compute series always, and re-resolves recipes from the
// cache when present (or from the network with --net).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const RES = path.join(repo, 'EconByte', 'Resources');
export const CATALOG_FILES = {
  core: path.join(RES, 'curriculum-v1.1.json'),
  packs: path.join(RES, 'packs-v1.json'),
};
const CACHE = process.env.CARD_GRAPHICS_CACHE || path.join(os.tmpdir(), 'econbyte-card-graphics-cache');

export const KINDS = ['bars', 'line', 'diagram', 'flow', 'compare', 'timeline', 'formula', 'proportion', 'icons'];
export const BASES = ['conceptual', 'fromCard', 'computed', 'sourced', 'illustrative'];
const APPROVED_SOURCE_HOSTS = new Set(['fred.stlouisfed.org', 'data.worldbank.org']);
const STALE_WORDS = ['currently', 'today', 'nowadays', 'recently', 'at present', 'these days',
  'this year', 'last year', 'right now', 'as of now'];
const ADVICE_PHRASES = ['you should buy', 'you should sell', 'you should invest', 'should buy',
  'should sell', 'invest in', 'buy now', 'sell now', 'guaranteed return', 'risk-free return',
  'financial advice', 'investment advice', 'we recommend', 'best investment', 'will outperform',
  'get rich', 'hot stock', 'price target', 'portfolio allocation', 'beat the market', 'sure thing', 'act fast'];
const NAMED = ['s&p', 'dow jones', 'nasdaq', 'russell 2000', 'ftse', 'nikkei', 'bitcoin', 'ethereum',
  'apple inc', 'tesla', 'amazon', 'microsoft', 'nvidia', 'vanguard', 'fidelity', 'schwab', 'blackrock'];
const DERIVED_CONSTANTS = new Set([1, 2, 4, 10, 12, 52, 100, 365, 1000]);
const MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12,
  january: 1, february: 2, march: 3, april: 4, june: 6, july: 7, august: 8, september: 9, october: 10, november: 11, december: 12 };
const WORD_NUMBERS = { zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9,
  ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17,
  eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70,
  eighty: 80, ninety: 90, hundred: 100, thousand: 1000, million: 1e6, billion: 1e9, trillion: 1e12,
  half: 0.5, double: 2, doubled: 2, doubles: 2, doubling: 2, twice: 2, triple: 3, tripled: 3, triples: 3,
  quadrupled: 4, quadruple: 4, first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6, seventh: 7,
  eighth: 8, ninth: 9, tenth: 10, dozen: 12, decade: 10, decades: 10, century: 100 };
const SCALE_WORDS = { thousand: 1e3, million: 1e6, billion: 1e9, trillion: 1e12 };

// ---------------------------------------------------------------------------
// Catalog loading

export function loadCatalogs() {
  const out = new Map();
  const core = JSON.parse(fs.readFileSync(CATALOG_FILES.core, 'utf8'));
  for (const t of core.topics) for (const c of t.cards) out.set(c.cardID, { card: c, file: 'core', group: `core/${t.topicID}` });
  const packs = JSON.parse(fs.readFileSync(CATALOG_FILES.packs, 'utf8'));
  for (const p of packs.packs) for (const t of p.topics) for (const c of t.cards) out.set(c.cardID, { card: c, file: 'packs', group: `${p.packID}/${t.topicID}` });
  return out;
}

// ---------------------------------------------------------------------------
// Numbers

const near = (a, b) => Math.abs(a - b) <= Math.max(1e-9, Math.abs(b) * 1e-9);

/** Every number a piece of prose states, with scaled forms ("1.2 million" → 1.2 and 1200000). */
export function proseNumbers(text) {
  const nums = [];
  const t = text.replace(/−/g, '-');
  const re = /(\d[\d,]*(?:\.\d+)?)(\s*(?:thousand|million|billion|trillion))?/gi;
  for (const m of t.matchAll(re)) {
    const raw = m[1].replace(/,+$/, '');
    // "1,000" is a thousands separator; "3,4" is a list. Accept only groups of 3.
    let v;
    if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(raw)) v = Number(raw.replace(/,/g, ''));
    else if (raw.includes(',')) { for (const part of raw.split(',')) if (part) nums.push(Number(part)); continue; }
    else v = Number(raw);
    if (!Number.isFinite(v)) continue;
    nums.push(v);
    if (m[2]) nums.push(v * SCALE_WORDS[m[2].trim().toLowerCase()]);
  }
  for (const w of t.toLowerCase().match(/[a-z]+/g) || []) if (w in WORD_NUMBERS) nums.push(WORD_NUMBERS[w]);
  // Fractions like "1 in 8" are covered by their parts; "90s" by 90.
  return nums;
}

/** Numbers that a display string of a graphic states (same rules as prose). */
export function displayNumbers(text) {
  const nums = [];
  const t = String(text).replace(/−/g, '-');
  const re = /(\d[\d,]*(?:\.\d+)?)(\s*(?:thousand|million|billion|trillion|k\b|m\b|bn\b|tn\b))?/gi;
  for (const m of t.matchAll(re)) {
    const raw = m[1].replace(/,+$/, '');
    let v;
    if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(raw)) v = Number(raw.replace(/,/g, ''));
    else if (raw.includes(',')) { for (const part of raw.split(',')) if (part) nums.push({ v: Number(part) }); continue; }
    else v = Number(raw);
    if (Number.isFinite(v)) nums.push({ v, text: m[0] });
  }
  return nums;
}

function allowedHas(allowed, v) {
  for (const a of allowed) {
    if (near(a, v)) return true;
    // Accept the same figure at display rounding: 9.06 in data shown as "9.1".
    if (Math.abs(a) >= 0.01 && Math.abs(a - v) <= 0.051 && Math.abs(v) < 1000 && !Number.isInteger(v)) return true;
  }
  return false;
}

// Safe arithmetic: numbers, + - * / ^ ( ).
export function evalExpr(expr) {
  const s = String(expr).replace(/−/g, '-').replace(/×/g, '*').replace(/÷/g, '/');
  if (!/^[\d\s.+\-*/^()]+$/.test(s)) throw new Error(`expr has disallowed characters: ${expr}`);
  let i = 0;
  const peek = () => { while (s[i] === ' ') i++; return s[i]; };
  const num = () => {
    peek(); const m = /^\d+(\.\d+)?/.exec(s.slice(i));
    if (!m) throw new Error(`bad number at ${i} in ${expr}`);
    i += m[0].length; return Number(m[0]);
  };
  const atom = () => {
    const c = peek();
    if (c === '(') { i++; const v = add(); if (peek() !== ')') throw new Error(`missing ) in ${expr}`); i++; return v; }
    if (c === '-') { i++; return -atom(); }
    return num();
  };
  const pow = () => { let v = atom(); if (peek() === '^') { i++; v = v ** pow(); } return v; };
  const mul = () => { let v = pow(); for (;;) { const c = peek(); if (c === '*') { i++; v *= pow(); } else if (c === '/') { i++; v /= pow(); } else return v; } };
  const add = () => { let v = mul(); for (;;) { const c = peek(); if (c === '+') { i++; v += mul(); } else if (c === '-') { i++; v -= mul(); } else return v; } };
  const v = add();
  if (peek() !== undefined) throw new Error(`trailing input in ${expr}`);
  return v;
}

export function exprLiterals(expr) {
  return (String(expr).match(/\d+(?:\.\d+)?/g) || []).map(Number);
}

// ---------------------------------------------------------------------------
// Dates

export function parseWhen(when) {
  const s = String(when).toLowerCase();
  const year = /(\d{4})/.exec(s);
  if (!year) return null;
  let month = 0, day = 0;
  for (const w of s.match(/[a-z]+/g) || []) if (w in MONTHS) { month = MONTHS[w]; break; }
  const withoutYear = s.replace(year[1], ' ');
  const d = /\b(\d{1,2})\b/.exec(withoutYear);
  if (d && month) day = Number(d[1]);
  return { year: Number(year[1]), month, day, key: Number(year[1]) * 10000 + month * 100 + day };
}

// ---------------------------------------------------------------------------
// Compute models

const r2 = (v) => Math.round(v * 100) / 100;

export function computeSeries(c) {
  const pts = [];
  const need = (...k) => { for (const key of k) if (typeof c[key] !== 'number' || !Number.isFinite(c[key])) throw new Error(`compute.${c.model} needs numeric ${key}`); };
  switch (c.model) {
    case 'compound': {
      need('principal', 'ratePct', 'years', 'step');
      const n = c.periodsPerYear ?? 1, r = c.ratePct / 100, contrib = c.contribution ?? 0;
      let bal = c.principal;
      const byYear = [c.principal];
      for (let y = 1; y <= c.years; y++) {
        bal = bal * (1 + r / n) ** n + contrib;
        byYear.push(bal);
      }
      for (let t = 0; t <= c.years; t += c.step) pts.push([t, r2(byYear[t])]);
      if ((c.years % c.step) !== 0) pts.push([c.years, r2(byYear[c.years])]);
      return pts;
    }
    case 'simple': {
      need('principal', 'ratePct', 'years', 'step');
      for (let t = 0; t <= c.years; t += c.step) pts.push([t, r2(c.principal * (1 + (c.ratePct / 100) * t))]);
      return pts;
    }
    case 'purchasingPower': {
      need('start', 'ratePct', 'years', 'step');
      for (let t = 0; t <= c.years; t += c.step) pts.push([t, r2(c.start / (1 + c.ratePct / 100) ** t)]);
      return pts;
    }
    case 'amortizationBalance':
    case 'amortizationInterestShare': {
      need('principal', 'aprPct', 'months', 'step');
      const i = c.aprPct / 100 / 12, N = c.months;
      const pay = i === 0 ? c.principal / N : c.principal * i / (1 - (1 + i) ** -N);
      let bal = c.principal;
      const balances = [bal], shares = [null];
      for (let m = 1; m <= N; m++) {
        const interest = bal * i;
        shares.push(100 * interest / pay);
        bal = bal - (pay - interest);
        balances.push(Math.max(0, bal));
      }
      if (c.model === 'amortizationBalance') {
        for (let m = 0; m <= N; m += c.step) pts.push([m, r2(balances[m])]);
        if (N % c.step !== 0) pts.push([N, r2(balances[N])]);
      } else {
        for (let m = 1; m <= N; m += c.step) pts.push([m, r2(shares[m])]);
        if ((N - 1) % c.step !== 0) pts.push([N, r2(shares[N])]);
      }
      return pts;
    }
    default:
      throw new Error(`unknown compute model ${c.model}`);
  }
}

export function computeInputs(c) {
  return Object.entries(c).filter(([k, v]) => k !== 'step' && k !== 'model' && typeof v === 'number').map(([k, v]) => ({ k, v }));
}

// ---------------------------------------------------------------------------
// Recipes

function cachePath(name) { fs.mkdirSync(CACHE, { recursive: true }); return path.join(CACHE, name); }

async function fetchText(url) {
  let lastErr;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(45000) });
      if (!res.ok) throw new Error(`${res.status} for ${url}`);
      return await res.text();
    } catch (e) { lastErr = e; await new Promise((r) => setTimeout(r, 1500 * (attempt + 1))); }
  }
  throw lastErr;
}

async function fredObservations(series, { net }) {
  const file = cachePath(`fred_${series}.csv`);
  if (!fs.existsSync(file)) {
    if (!net) return null;
    const text = await fetchText(`https://fred.stlouisfed.org/graph/fredgraph.csv?id=${encodeURIComponent(series)}`);
    if (!/^observation_date|^DATE/i.test(text)) throw new Error(`FRED ${series}: unexpected response`);
    fs.writeFileSync(file, text);
  }
  const rows = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/).slice(1);
  return rows.map((l) => l.split(',')).filter(([, v]) => v !== '.' && v !== '' && v !== undefined)
    .map(([d, v]) => ({ y: Number(d.slice(0, 4)), m: Number(d.slice(5, 7)), v: Number(v) }));
}

async function worldBankObservations(indicator, country, { net }) {
  const file = cachePath(`wb_${indicator}_${country}.json`);
  if (!fs.existsSync(file)) {
    if (!net) return null;
    const text = await fetchText(`https://api.worldbank.org/v2/country/${encodeURIComponent(country)}/indicator/${encodeURIComponent(indicator)}?format=json&per_page=20000`);
    const parsed = JSON.parse(text);
    if (!Array.isArray(parsed) || !Array.isArray(parsed[1])) throw new Error(`World Bank ${indicator}/${country}: unexpected response`);
    fs.writeFileSync(file, text);
  }
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  return parsed[1].filter((o) => o.value !== null).map((o) => ({ y: Number(o.date), m: 1, v: Number(o.value) })).sort((a, b) => a.y - b.y);
}

const round = (v, d) => { const f = 10 ** d; return Math.round(v * f) / f; };
const ym = (s) => { const [y, m] = String(s).split('-').map(Number); return y * 12 + ((m || 1) - 1); };

export async function resolveRecipe(recipe, { net = false } = {}) {
  const d = recipe.decimals ?? 1;
  if (recipe.provider === 'worldbank') {
    const obs = await worldBankObservations(recipe.indicator, recipe.country, { net });
    if (!obs) return null;
    return obs.filter((o) => o.y >= Number(recipe.from) && o.y <= Number(recipe.to)).map((o) => [o.y, round(o.v, d)]);
  }
  if (recipe.provider !== 'fred') throw new Error(`unknown recipe provider ${recipe.provider}`);
  const obs = await fredObservations(recipe.series, { net });
  if (!obs) return null;
  // Frequency from spacing.
  const gap = obs.length > 2 ? (obs[1].y * 12 + obs[1].m) - (obs[0].y * 12 + obs[0].m) : 1;
  const lag = { pct_change_12m: 12, pct_change_4q: 4, pct_change_1y: 1 }[recipe.transform];
  let series = obs;
  if (recipe.transform !== 'level') {
    if (!lag) throw new Error(`unknown transform ${recipe.transform}`);
    const expectGap = { pct_change_12m: 1, pct_change_4q: 3, pct_change_1y: 12 }[recipe.transform];
    if (gap !== expectGap) throw new Error(`${recipe.series}: ${recipe.transform} needs observations every ${expectGap} month(s), found ${gap}`);
    const idx = new Map(obs.map((o) => [o.y * 12 + o.m, o.v]));
    series = obs.map((o) => {
      const prev = idx.get(o.y * 12 + o.m - lag * expectGap);
      return prev === undefined ? null : { ...o, v: 100 * (o.v / prev - 1) };
    }).filter(Boolean);
  }
  const lo = ym(recipe.from), hi = ym(recipe.to);
  series = series.filter((o) => { const k = o.y * 12 + (o.m - 1); return k >= lo && k <= hi; });
  const sample = recipe.sample || 'all';
  if (sample === 'all') return series.map((o) => [round(o.y + (o.m - 1) / 12, 4), round(o.v, d)]);
  const years = [...new Set(series.map((o) => o.y))];
  if (sample === 'annual_mean') {
    const perYear = gap === 1 ? 12 : gap === 3 ? 4 : 1;
    return years.map((y) => {
      const vals = series.filter((o) => o.y === y).map((o) => o.v);
      return vals.length === perYear ? [y, round(vals.reduce((a, b) => a + b, 0) / vals.length, d)] : null;
    }).filter(Boolean);
  }
  if (sample === 'year_end') return years.map((y) => { const v = series.filter((o) => o.y === y); return [y, round(v[v.length - 1].v, d)]; });
  const mm = /^month:(\d{2})$/.exec(sample);
  if (mm) return years.map((y) => { const o = series.find((x) => x.y === y && x.m === Number(mm[1])); return o ? [y, round(o.v, d)] : null; }).filter(Boolean);
  throw new Error(`unknown sample ${sample}`);
}

// ---------------------------------------------------------------------------
// Validation

const len = (s) => [...String(s ?? '')].length;
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isStr = (v) => typeof v === 'string' && v.trim().length > 0;

/** Every displayed string of a spec, with where it lives. */
export function displayStrings(spec) {
  const out = [];
  const push = (where, s) => { if (typeof s === 'string') out.push({ where, s }); };
  push('title', spec.title); push('note', spec.note);
  const p = spec[spec.kind] || {};
  switch (spec.kind) {
    case 'bars':
      push('bars.unit.prefix', p.unit?.prefix); push('bars.unit.suffix', p.unit?.suffix);
      (p.items || []).forEach((it, i) => { push(`bars.items[${i}].label`, it.label); push(`bars.items[${i}].display`, it.display); });
      break;
    case 'line':
      push('line.xLabel', p.xLabel); push('line.yLabel', p.yLabel);
      (p.series || []).forEach((s, i) => push(`line.series[${i}].name`, s.name));
      (p.markers || []).forEach((m, i) => push(`line.markers[${i}].label`, m.label));
      (p.references || []).forEach((m, i) => push(`line.references[${i}].label`, m.label));
      break;
    case 'diagram':
      push('diagram.xLabel', p.xLabel); push('diagram.yLabel', p.yLabel);
      (p.curves || []).forEach((c, i) => push(`diagram.curves[${i}].label`, c.label));
      (p.dots || []).forEach((c, i) => push(`diagram.dots[${i}].label`, c.label));
      (p.guides || []).forEach((c, i) => push(`diagram.guides[${i}].label`, c.label));
      (p.arrows || []).forEach((c, i) => push(`diagram.arrows[${i}].label`, c.label));
      break;
    case 'flow':
      (p.steps || []).forEach((st, i) => { push(`flow.steps[${i}].title`, st.title); push(`flow.steps[${i}].detail`, st.detail); });
      break;
    case 'compare':
      (p.columns || []).forEach((c, i) => push(`compare.columns[${i}]`, c));
      (p.rows || []).forEach((r, i) => { push(`compare.rows[${i}].label`, r.label); (r.values || []).forEach((v, j) => push(`compare.rows[${i}].values[${j}]`, v)); });
      break;
    case 'timeline':
      (p.events || []).forEach((e, i) => { push(`timeline.events[${i}].when`, e.when); push(`timeline.events[${i}].label`, e.label); });
      break;
    case 'formula':
      push('formula.expression', p.expression); push('formula.example', p.example);
      (p.terms || []).forEach((t, i) => { push(`formula.terms[${i}].symbol`, t.symbol); push(`formula.terms[${i}].meaning`, t.meaning); });
      break;
    case 'proportion':
      push('proportion.unitLabel', p.unitLabel); push('proportion.remainderLabel', p.remainderLabel);
      (p.segments || []).forEach((s, i) => push(`proportion.segments[${i}].label`, s.label));
      break;
    case 'icons':
      (p.items || []).forEach((it, i) => push(`icons.items[${i}].label`, it.label));
      break;
  }
  return out;
}

/** Numeric data values of a spec (not unit-space coordinates, not recipe/compute parameters). */
function dataValues(spec) {
  const out = [];
  const p = spec[spec.kind] || {};
  if (spec.kind === 'bars') (p.items || []).forEach((it, i) => out.push({ where: `bars.items[${i}].value`, v: it.value }));
  if (spec.kind === 'line') {
    (p.series || []).forEach((s, i) => (s.points || []).forEach((pt, j) => { out.push({ where: `line.series[${i}].points[${j}].x`, v: pt[0], x: true }); out.push({ where: `line.series[${i}].points[${j}].y`, v: pt[1] }); }));
    (p.markers || []).forEach((m, i) => out.push({ where: `line.markers[${i}].x`, v: m.x, x: true, marker: true }));
    (p.references || []).forEach((m, i) => out.push({ where: `line.references[${i}].y`, v: m.y }));
  }
  if (spec.kind === 'proportion') {
    out.push({ where: 'proportion.total', v: p.total, total: true });
    (p.segments || []).forEach((s, i) => out.push({ where: `proportion.segments[${i}].value`, v: s.value }));
  }
  return out;
}

const LIMITS = {
  title: 56, note: 90, barLabel: 26, barDisplay: 16, markerLabel: 18, diagramLabel: 18, axisLabel: 24,
  flowTitle: 34, flowDetail: 48, compareHead: 16, compareLabel: 16, compareValue: 24, when: 14, eventLabel: 40,
  expression: 40, symbol: 8, meaning: 32, example: 60, segLabel: 22, unitLabel: 34, iconLabel: 18, seriesName: 28,
};

export function validateSpec(spec, card, { resolved = null } = {}) {
  const errors = [], warnings = [];
  const fail = (w, m) => errors.push(`${w}: ${m}`);
  const warn = (w, m) => warnings.push(`${w}: ${m}`);
  if (!spec || typeof spec !== 'object') { fail('graphic', 'missing'); return { errors, warnings }; }
  if (!KINDS.includes(spec.kind)) fail('kind', `unknown kind ${spec.kind}`);
  if (!BASES.includes(spec.basis)) fail('basis', `unknown basis ${spec.basis}`);
  if (!isStr(spec.title) || len(spec.title) > LIMITS.title) fail('title', `required, ≤ ${LIMITS.title} chars (${len(spec.title)})`);
  if (spec.title && /\.$/.test(spec.title.trim())) fail('title', 'no final period');
  if (spec.note !== undefined && (!isStr(spec.note) || len(spec.note) > LIMITS.note)) fail('note', `≤ ${LIMITS.note} chars`);
  for (const k of KINDS) if (k !== spec.kind && spec[k] !== undefined) fail(k, `payload for ${k} present on a ${spec.kind} graphic`);
  const p = spec[spec.kind];
  if (!p || typeof p !== 'object') { fail(spec.kind, 'payload missing'); return { errors, warnings }; }
  const within = (w, s, max, required = true) => {
    if (s === undefined || s === null) { if (required) fail(w, 'required'); return; }
    if (typeof s !== 'string') return fail(w, 'must be a string');
    if (required && !s.trim()) return fail(w, 'must not be empty');
    if (len(s) > max) fail(w, `≤ ${max} chars (${len(s)}: "${s}")`);
  };
  const unit01 = (w, v) => { if (!isNum(v) || v < 0 || v > 1) fail(w, `must be in [0, 1], got ${v}`); };

  switch (spec.kind) {
    case 'bars': {
      const items = p.items || [];
      if (items.length < 2 || items.length > 6) fail('bars.items', `2–6 items, got ${items.length}`);
      items.forEach((it, i) => {
        within(`bars.items[${i}].label`, it.label, LIMITS.barLabel);
        if (!isNum(it.value) || it.value < 0) fail(`bars.items[${i}].value`, 'number ≥ 0');
        if (it.display !== undefined) within(`bars.items[${i}].display`, it.display, LIMITS.barDisplay);
      });
      if (items.filter((it) => it.emphasis).length > 2) fail('bars.items', 'at most 2 emphasized');
      if (p.decimals !== undefined && (!Number.isInteger(p.decimals) || p.decimals < 0 || p.decimals > 3)) fail('bars.decimals', '0–3');
      if (items.length && items.every((it) => it.value === 0)) fail('bars.items', 'all values are zero');
      break;
    }
    case 'line': {
      within('line.xLabel', p.xLabel, LIMITS.axisLabel); within('line.yLabel', p.yLabel, LIMITS.axisLabel);
      if (!['year', 'month', 'number'].includes(p.xFormat)) fail('line.xFormat', 'year | month | number');
      const series = p.series || [];
      if (series.length < 1 || series.length > 3) fail('line.series', `1–3 series, got ${series.length}`);
      series.forEach((s, i) => {
        within(`line.series[${i}].name`, s.name, LIMITS.seriesName);
        const pts = s.points || [];
        if (pts.length < 2 || pts.length > 60) fail(`line.series[${i}].points`, `2–60 points, got ${pts.length}`);
        pts.forEach((pt, j) => { if (!Array.isArray(pt) || pt.length !== 2 || !isNum(pt[0]) || !isNum(pt[1])) fail(`line.series[${i}].points[${j}]`, 'must be [x, y] numbers'); });
        for (let j = 1; j < pts.length; j++) if (!(pts[j][0] > pts[j - 1][0])) fail(`line.series[${i}].points`, `x must strictly increase (at ${j})`);
        if (spec.basis === 'sourced' && !s.recipe) fail(`line.series[${i}]`, 'a sourced series needs a recipe');
        if (spec.basis === 'computed' && !s.compute) fail(`line.series[${i}]`, 'a computed series needs compute');
        if (s.recipe && s.compute) fail(`line.series[${i}]`, 'recipe and compute are exclusive');
        if ((s.recipe || s.compute) && spec.basis !== 'sourced' && spec.basis !== 'computed') fail(`line.series[${i}]`, `recipe/compute on a ${spec.basis} graphic`);
      });
      const xs = series.flatMap((s) => (s.points || []).map((pt) => pt[0]));
      const [xmin, xmax] = [Math.min(...xs), Math.max(...xs)];
      if ((p.markers || []).length > 2) fail('line.markers', 'at most 2');
      (p.markers || []).forEach((m, i) => { within(`line.markers[${i}].label`, m.label, LIMITS.markerLabel); if (!isNum(m.x) || m.x < xmin || m.x > xmax) fail(`line.markers[${i}].x`, `inside the x range ${xmin}–${xmax}`); });
      if ((p.references || []).length > 2) fail('line.references', 'at most 2');
      (p.references || []).forEach((m, i) => { within(`line.references[${i}].label`, m.label, LIMITS.markerLabel); if (!isNum(m.y)) fail(`line.references[${i}].y`, 'number'); });
      if (p.decimals !== undefined && (!Number.isInteger(p.decimals) || p.decimals < 0 || p.decimals > 3)) fail('line.decimals', '0–3');
      break;
    }
    case 'diagram': {
      if (!['conceptual', 'illustrative'].includes(spec.basis)) fail('basis', 'a diagram is conceptual or illustrative');
      within('diagram.xLabel', p.xLabel, LIMITS.axisLabel); within('diagram.yLabel', p.yLabel, LIMITS.axisLabel);
      const curves = p.curves || [];
      if (curves.length < 1 || curves.length > 4) fail('diagram.curves', `1–4 curves, got ${curves.length}`);
      curves.forEach((c, i) => {
        within(`diagram.curves[${i}].label`, c.label, LIMITS.diagramLabel, false);
        const pts = c.points || [];
        if (pts.length < 2 || pts.length > 12) fail(`diagram.curves[${i}].points`, '2–12 points');
        pts.forEach((pt, j) => { unit01(`diagram.curves[${i}].points[${j}].x`, pt?.[0]); unit01(`diagram.curves[${i}].points[${j}].y`, pt?.[1]); });
        if (c.style !== undefined && !['solid', 'dashed'].includes(c.style)) fail(`diagram.curves[${i}].style`, 'solid | dashed');
        if (c.tone !== undefined && !['primary', 'accent', 'muted'].includes(c.tone)) fail(`diagram.curves[${i}].tone`, 'primary | accent | muted');
      });
      if ((p.dots || []).length > 3) fail('diagram.dots', 'at most 3');
      (p.dots || []).forEach((d, i) => { unit01(`diagram.dots[${i}].x`, d.x); unit01(`diagram.dots[${i}].y`, d.y); within(`diagram.dots[${i}].label`, d.label, LIMITS.diagramLabel, false); });
      if ((p.guides || []).length > 3) fail('diagram.guides', 'at most 3');
      (p.guides || []).forEach((g, i) => { if (!['x', 'y'].includes(g.axis)) fail(`diagram.guides[${i}].axis`, 'x | y'); unit01(`diagram.guides[${i}].at`, g.at); within(`diagram.guides[${i}].label`, g.label, LIMITS.diagramLabel, false); });
      if ((p.arrows || []).length > 2) fail('diagram.arrows', 'at most 2');
      (p.arrows || []).forEach((a, i) => { [0, 1].forEach((k) => { unit01(`diagram.arrows[${i}].from[${k}]`, a.from?.[k]); unit01(`diagram.arrows[${i}].to[${k}]`, a.to?.[k]); }); within(`diagram.arrows[${i}].label`, a.label, LIMITS.diagramLabel, false); });
      break;
    }
    case 'flow': {
      if (!['chain', 'cycle'].includes(p.layout)) fail('flow.layout', 'chain | cycle');
      const steps = p.steps || [];
      const [lo, hi] = p.layout === 'cycle' ? [3, 4] : [2, 4];
      if (steps.length < lo || steps.length > hi) fail('flow.steps', `${lo}–${hi} steps for ${p.layout}, got ${steps.length}`);
      if (p.layout === 'chain' && steps.length === 4 && steps.some((st) => st.detail !== undefined)) fail('flow.steps', 'a 4-step chain has no details (too tall for the card)');
      steps.forEach((st, i) => {
        within(`flow.steps[${i}].title`, st.title, LIMITS.flowTitle);
        if (st.detail !== undefined) {
          within(`flow.steps[${i}].detail`, st.detail, LIMITS.flowDetail);
          if (p.layout === 'cycle') fail(`flow.steps[${i}].detail`, 'a cycle step has no detail');
        }
      });
      break;
    }
    case 'compare': {
      const cols = p.columns || [];
      if (cols.length < 2 || cols.length > 3) fail('compare.columns', '2–3 columns');
      cols.forEach((c, i) => within(`compare.columns[${i}]`, c, LIMITS.compareHead));
      const rows = p.rows || [];
      if (rows.length < 2 || rows.length > 4) fail('compare.rows', `2–4 rows, got ${rows.length}`);
      rows.forEach((r, i) => {
        if (typeof r.label !== 'string') fail(`compare.rows[${i}].label`, 'string (may be empty)');
        else if (len(r.label) > LIMITS.compareLabel) fail(`compare.rows[${i}].label`, `≤ ${LIMITS.compareLabel} chars (${len(r.label)}: "${r.label}")`);
        if (!Array.isArray(r.values) || r.values.length !== cols.length) fail(`compare.rows[${i}].values`, `exactly ${cols.length} values`);
        (r.values || []).forEach((v, j) => within(`compare.rows[${i}].values[${j}]`, v, LIMITS.compareValue));
      });
      break;
    }
    case 'timeline': {
      const ev = p.events || [];
      if (ev.length < 2 || ev.length > 5) fail('timeline.events', `2–5 events, got ${ev.length}`);
      let prev = null;
      ev.forEach((e, i) => {
        within(`timeline.events[${i}].when`, e.when, LIMITS.when);
        within(`timeline.events[${i}].label`, e.label, LIMITS.eventLabel);
        const d = parseWhen(e.when);
        if (!d) fail(`timeline.events[${i}].when`, 'needs a four-digit year');
        else { if (prev && d.key < prev.key) fail(`timeline.events[${i}].when`, `out of order: ${e.when} after ${prev.when}`); prev = { ...d, when: e.when }; }
      });
      break;
    }
    case 'formula': {
      within('formula.expression', p.expression, LIMITS.expression);
      const terms = p.terms || [];
      if (terms.length < 1 || terms.length > 5) fail('formula.terms', '1–5 terms');
      terms.forEach((t, i) => { within(`formula.terms[${i}].symbol`, t.symbol, LIMITS.symbol); within(`formula.terms[${i}].meaning`, t.meaning, LIMITS.meaning); });
      if (p.example !== undefined) within('formula.example', p.example, LIMITS.example);
      if (/[*/]|\s-\s/.test(p.expression || '')) warn('formula.expression', 'use × ÷ − for display');
      break;
    }
    case 'proportion': {
      if (!['bar', 'waffle'].includes(p.style)) fail('proportion.style', 'bar | waffle');
      if (!isNum(p.total) || p.total <= 0) fail('proportion.total', 'number > 0');
      const segs = p.segments || [];
      if (segs.length < 1 || segs.length > 4) fail('proportion.segments', '1–4 segments');
      segs.forEach((s, i) => { within(`proportion.segments[${i}].label`, s.label, LIMITS.segLabel); if (!isNum(s.value) || s.value < 0) fail(`proportion.segments[${i}].value`, 'number ≥ 0'); });
      const sum = segs.reduce((a, s) => a + (isNum(s.value) ? s.value : 0), 0);
      if (isNum(p.total) && sum > p.total * (1 + 1e-9)) fail('proportion.segments', `sum ${sum} exceeds total ${p.total}`);
      if (isNum(p.total) && sum < p.total - 1e-9) within('proportion.remainderLabel', p.remainderLabel, LIMITS.segLabel);
      if (p.unitLabel !== undefined) within('proportion.unitLabel', p.unitLabel, LIMITS.unitLabel);
      if (p.style === 'waffle') {
        if (![10, 20, 50, 100].includes(p.total)) fail('proportion.total', 'waffle total ∈ {10, 20, 50, 100}');
        segs.forEach((s, i) => { if (!Number.isInteger(s.value)) fail(`proportion.segments[${i}].value`, 'waffle values are integers'); });
      }
      break;
    }
    case 'icons': {
      if (!['plus', 'arrow', 'versus', 'equals', 'none'].includes(p.connector)) fail('icons.connector', 'plus | arrow | versus | equals | none');
      const items = p.items || [];
      if (items.length < 2 || items.length > 4) fail('icons.items', '2–4 items');
      items.forEach((it, i) => { within(`icons.items[${i}].label`, it.label, LIMITS.iconLabel); if (!isStr(it.symbol) || !/^[a-z0-9.]+$/.test(it.symbol)) fail(`icons.items[${i}].symbol`, 'SF Symbol name'); });
      break;
    }
  }

  // House rules on every displayed string.
  const strings = displayStrings(spec);
  for (const { where, s } of strings) {
    const lower = s.toLowerCase();
    for (const w of STALE_WORDS) if (new RegExp(`\\b${w}\\b`).test(lower)) fail(where, `stale wording "${w}"`);
    for (const a of ADVICE_PHRASES) if (lower.includes(a)) fail(where, `advice framing "${a}"`);
    for (const n of NAMED) if (lower.includes(n)) fail(where, `names a brand/index "${n}"`);
    for (const m of s.matchAll(/\b(\d{4})\b/g)) if (Number(m[1]) > 2026 && Number(m[1]) < 2200) fail(where, `year ${m[1]} after 2026`);
    if (/[‘’]/.test(s) === false && /\s{2,}/.test(s)) warn(where, 'double space');
    if (/colour|behaviour|favour|centre|labour(?! party)|organis|analys(e|ing)\b|licence/i.test(s)) fail(where, 'British spelling');
  }

  // Basis rules.
  if (spec.basis === 'sourced') {
    const src = spec.source;
    if (!src) fail('source', 'required for sourced');
    else {
      for (const k of ['organization', 'title', 'url', 'period', 'retrieved']) if (!isStr(src[k])) fail(`source.${k}`, 'required');
      try {
        const u = new URL(src.url);
        if (u.protocol !== 'https:') fail('source.url', 'https');
        if (!APPROVED_SOURCE_HOSTS.has(u.hostname)) fail('source.url', `host ${u.hostname} not approved for graphics`);
        if (u.search || u.hash) fail('source.url', 'no query or fragment');
      } catch { fail('source.url', 'not a URL'); }
      if (src.retrieved && !/^\d{4}-\d{2}-\d{2}$/.test(src.retrieved)) fail('source.retrieved', 'YYYY-MM-DD');
    }
  } else if (spec.source !== undefined) fail('source', `only sourced graphics carry a source (basis ${spec.basis})`);
  if (spec.basis === 'computed' && spec.kind !== 'line') fail('basis', 'computed applies to line series only (use derived for single values)');
  if (spec.basis === 'sourced' && spec.kind !== 'line') fail('basis', 'sourced applies to line series only');

  const cardText = card ? `${card.title} ${card.definition} ${card.example}` : '';
  const cardNums = card ? proseNumbers(cardText) : [];
  const allowed = [...cardNums];
  (spec.derived || []).forEach((d, i) => {
    if (!isNum(d.value) || !isStr(d.expr)) return fail(`derived[${i}]`, 'needs value and expr');
    let v;
    try { v = evalExpr(d.expr); } catch (e) { return fail(`derived[${i}].expr`, e.message); }
    if (!(Math.abs(v - d.value) <= Math.max(Math.abs(v) * 0.005, 0.05))) fail(`derived[${i}]`, `${d.expr} = ${v}, not ${d.value}`);
    for (const lit of exprLiterals(d.expr)) if (!DERIVED_CONSTANTS.has(lit) && !cardNums.some((c) => near(c, lit))) fail(`derived[${i}].expr`, `literal ${lit} is not in the card text`);
    allowed.push(d.value);
  });
  if (spec.derived !== undefined && spec.basis === 'conceptual') fail('derived', 'a conceptual graphic has no numbers');

  // Resolved/computed series checks.
  if (spec.kind === 'line') {
    for (const [i, s] of (p.series || []).entries()) {
      if (s.compute) {
        let expect;
        try { expect = computeSeries(s.compute); } catch (e) { fail(`line.series[${i}].compute`, e.message); continue; }
        if (JSON.stringify(expect) !== JSON.stringify(s.points)) fail(`line.series[${i}].points`, `do not match compute (${JSON.stringify(expect).slice(0, 120)}…)`);
        for (const { k, v } of computeInputs(s.compute)) if (!cardNums.some((c) => near(c, v)) && !(spec.derived || []).some((d) => near(d.value, v))) fail(`line.series[${i}].compute.${k}`, `input ${v} is not in the card text`);
        allowed.push(...(s.points || []).flatMap((pt) => [pt[0], pt[1]]));
      }
      if (s.recipe) {
        const r = resolved?.get(s);
        if (r === undefined) warn(`line.series[${i}].recipe`, 'not re-resolved (no cache; run with --net)');
        else if (r !== null && JSON.stringify(r) !== JSON.stringify(s.points)) fail(`line.series[${i}].points`, `do not match the recipe data (${JSON.stringify(r).slice(0, 120)}…)`);
        allowed.push(...(s.points || []).flatMap((pt) => [pt[0], pt[1]]));
      }
    }
  }

  // Numbers vs basis.
  const shown = [];
  // "12-month change" names a measure, not a figure; a waffle's own total is its grid size.
  for (const { where, s } of strings) for (const n of displayNumbers(s.replace(/\b12-month\b/gi, 'twelve-month'))) shown.push({ where, v: n.v, text: n.text });
  if (spec.kind === 'proportion' && p.style === 'waffle' && isNum(p.total)) allowed.push(p.total);
  const data = dataValues(spec);
  if (spec.basis === 'conceptual') {
    for (const { where, s } of strings) if (/\d/.test(s)) fail(where, `a conceptual graphic shows no numbers ("${s}")`);
  } else if (spec.basis === 'fromCard' || spec.basis === 'computed' || spec.basis === 'sourced') {
    for (const n of shown) if (!allowedHas(allowed, n.v)) fail(n.where, `number ${n.text?.trim() ?? n.v} is not in the card text, derived, or data`);
    for (const d of data) {
      if (spec.kind === 'line' && (p.series || []).some((s) => s.compute || s.recipe) && !d.marker && !d.where.startsWith('line.references')) continue;
      if (d.total && spec.kind === 'proportion' && [10, 20, 50, 100].includes(d.v)) continue;
      if (d.where.startsWith('line.references') && d.v === 0) continue;
      if (d.marker) {
        // A marker must sit on a data point's x, or on a year/month named in the card.
        const onPoint = (p.series || []).some((s) => (s.points || []).some((pt) => near(pt[0], d.v)));
        if (!onPoint && !allowedHas(allowed, Math.floor(d.v))) fail(d.where, `marker x ${d.v} is neither a data point nor a card year`);
        continue;
      }
      if (!allowedHas(allowed, d.v)) fail(d.where, `value ${d.v} is not in the card text, derived, or data`);
    }
  } else if (spec.basis === 'illustrative') {
    const off = [...shown.map((n) => n.v), ...data.filter((d) => !d.total).map((d) => d.v)].filter((v) => !allowedHas(allowed, v));
    if (off.length) warn('illustrative', `numbers not in the card (review for contradiction): ${[...new Set(off)].slice(0, 8).join(', ')}`);
  }

  // Bars/proportion: when every value is shown with a percent sign, a whole-split must not exceed 100.
  if (spec.kind === 'proportion' && /percent|%/.test(`${p.unitLabel ?? ''}`) && p.total !== 100) warn('proportion', 'percent unit with a total other than 100');
  return { errors, warnings };
}

// ---------------------------------------------------------------------------
// Resolution

export async function resolveSpec(spec, { net = false, write = false } = {}) {
  const resolved = new Map();
  if (spec?.kind !== 'line') return resolved;
  for (const s of spec.line?.series || []) {
    if (s.compute && write) s.points = computeSeries(s.compute);
    if (s.recipe) {
      let pts = null;
      try { pts = await resolveRecipe(s.recipe, { net }); } catch (e) { pts = { error: e.message }; }
      if (pts && pts.error) { resolved.set(s, null); s.__error = pts.error; continue; }
      resolved.set(s, pts);
      if (write && pts) s.points = pts;
    }
  }
  return resolved;
}

// ---------------------------------------------------------------------------
// Text-preserving merge

/** Minimal JSON scanner that records object key/value spans. */
function scan(text) {
  let i = 0;
  const ws = () => { while (i < text.length && /\s/.test(text[i])) i++; };
  const str = () => { const start = i; i++; while (text[i] !== '"') { if (text[i] === '\\') i++; i++; } i++; return { start, end: i, value: JSON.parse(text.slice(start, i)) }; };
  const objects = [];
  const value = () => {
    ws();
    const start = i;
    const c = text[i];
    if (c === '{') {
      i++; const keys = [];
      ws();
      if (text[i] === '}') { i++; const o = { type: 'object', start, end: i, keys }; objects.push(o); return o; }
      for (;;) {
        ws(); const k = str(); ws(); i++; // :
        const v = value(); keys.push({ key: k.value, keyStart: k.start, valueStart: v.start, valueEnd: v.end, node: v });
        ws(); if (text[i] === ',') { i++; continue; } if (text[i] === '}') { i++; break; }
        throw new Error(`scan: unexpected ${text[i]} at ${i}`);
      }
      const o = { type: 'object', start, end: i, keys }; objects.push(o); return o;
    }
    if (c === '[') {
      i++; ws();
      if (text[i] === ']') { i++; return { type: 'array', start, end: i }; }
      for (;;) { value(); ws(); if (text[i] === ',') { i++; continue; } if (text[i] === ']') { i++; break; } throw new Error(`scan: unexpected ${text[i]} at ${i}`); }
      return { type: 'array', start, end: i };
    }
    if (c === '"') { const s = str(); return { type: 'string', start: s.start, end: s.end }; }
    const m = /^(-?\d+(\.\d+)?([eE][+-]?\d+)?|true|false|null)/.exec(text.slice(i));
    if (!m) throw new Error(`scan: bad token at ${i}`);
    i += m[0].length; return { type: 'scalar', start, end: i };
  };
  value();
  return objects;
}

function cardObjects(text) {
  const map = new Map();
  for (const o of scan(text)) {
    const idKey = o.keys.find((k) => k.key === 'cardID');
    if (idKey && o.keys.some((k) => k.key === 'definition')) map.set(JSON.parse(text.slice(idKey.valueStart, idKey.valueEnd)), o);
  }
  return map;
}

function cleanSpec(spec) {
  return JSON.parse(JSON.stringify(spec, (k, v) => (k.startsWith('__') ? undefined : v)));
}

/** Pretty-print like the catalogs: 2-space indent, but short numeric pairs on one line. */
function stringifySpec(spec, indent) {
  let s = JSON.stringify(cleanSpec(spec), null, 2);
  s = s.replace(/\[\s+(-?[\d.eE+-]+),\s+(-?[\d.eE+-]+)\s+\]/g, '[$1, $2]');
  return s.split('\n').map((line, n) => (n === 0 ? line : indent + line)).join('\n');
}

export function mergeInto(text, specs) {
  const objs = cardObjects(text);
  const edits = [];
  for (const [id, spec] of Object.entries(specs)) {
    const o = objs.get(id);
    if (!o) continue;
    const first = o.keys[0];
    const lineStart = text.lastIndexOf('\n', first.keyStart) + 1;
    const indent = text.slice(lineStart, first.keyStart);
    const existing = o.keys.find((k) => k.key === 'graphic');
    const body = stringifySpec(spec, indent);
    if (existing) edits.push({ start: existing.valueStart, end: existing.valueEnd, insert: body });
    else {
      const last = o.keys[o.keys.length - 1];
      edits.push({ start: last.valueEnd, end: last.valueEnd, insert: `,\n${indent}"graphic": ${body}` });
    }
  }
  edits.sort((a, b) => b.start - a.start);
  let out = text;
  for (const e of edits) out = out.slice(0, e.start) + e.insert + out.slice(e.end);
  return { text: out, applied: edits.length };
}

// ---------------------------------------------------------------------------
// CLI

function readFragment(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  return raw.specs ?? raw;
}

function report(title, results, { quiet = false } = {}) {
  let e = 0, w = 0;
  for (const [id, r] of results) {
    e += r.errors.length; w += r.warnings.length;
    if (r.errors.length || (!quiet && r.warnings.length)) {
      console.log(`\n${id}`);
      for (const m of r.errors) console.log(`  ERROR ${m}`);
      if (!quiet) for (const m of r.warnings) console.log(`  warn  ${m}`);
    }
  }
  console.log(`\n${title}: ${results.size} graphics, ${e} errors, ${w} warnings`);
  return e;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const flags = new Set(rest.filter((a) => a.startsWith('--')));
  const args = rest.filter((a) => !a.startsWith('--'));
  const net = flags.has('--net');
  const cards = loadCatalogs();

  if (cmd === 'check-fragment' || cmd === 'resolve-fragment') {
    const file = args[0];
    const specs = readFragment(file);
    const results = new Map();
    for (const [id, spec] of Object.entries(specs)) {
      const entry = cards.get(id);
      const resolved = await resolveSpec(spec, { net: net || cmd === 'resolve-fragment', write: cmd === 'resolve-fragment' });
      const r = entry ? validateSpec(spec, entry.card, { resolved }) : { errors: [`unknown cardID ${id}`], warnings: [] };
      for (const s of spec?.line?.series || []) if (s.__error) r.errors.push(`recipe: ${s.__error}`);
      results.set(id, r);
    }
    if (cmd === 'resolve-fragment') {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
      const cleaned = Object.fromEntries(Object.entries(specs).map(([k, v]) => [k, cleanSpec(v)]));
      fs.writeFileSync(file, JSON.stringify(raw.specs ? { ...raw, specs: cleaned } : cleaned, null, 2) + '\n');
    }
    const errs = report(path.basename(file), results, { quiet: flags.has('--quiet') });
    process.exit(errs ? 1 : 0);
  }

  if (cmd === 'merge') {
    const all = {};
    for (const f of args) Object.assign(all, readFragment(f));
    for (const [id, spec] of Object.entries(all)) {
      if (!cards.has(id)) throw new Error(`merge: unknown cardID ${id}`);
      const r = validateSpec(spec, cards.get(id).card, { resolved: await resolveSpec(spec, { net: false }) });
      if (r.errors.length) throw new Error(`merge: ${id} has errors; run check-fragment first\n  ${r.errors.join('\n  ')}`);
    }
    for (const [which, file] of Object.entries(CATALOG_FILES)) {
      const text = fs.readFileSync(file, 'utf8');
      const mine = Object.fromEntries(Object.entries(all).filter(([id]) => cards.get(id).file === which));
      const { text: out, applied } = mergeInto(text, mine);
      // Structural proof: the result parses and differs from the original only by graphic fields.
      const before = JSON.parse(text), after = JSON.parse(out);
      const strip = (o) => JSON.stringify(o, (k, v) => (k === 'graphic' ? undefined : v));
      if (strip(before) !== strip(after)) throw new Error(`merge: ${which} changed outside graphic fields`);
      fs.writeFileSync(file, out);
      console.log(`${path.basename(file)}: ${applied} graphics merged`);
    }
    return;
  }

  if (cmd === 'check' || cmd === 'stats' || cmd === 'dump') {
    const results = new Map();
    const counts = { kind: {}, basis: {}, missing: [] };
    for (const [id, { card, group }] of cards) {
      if (!card.graphic) { counts.missing.push(id); continue; }
      const g = card.graphic;
      counts.kind[g.kind] = (counts.kind[g.kind] || 0) + 1;
      counts.basis[g.basis] = (counts.basis[g.basis] || 0) + 1;
      if (cmd === 'check') {
        const resolved = await resolveSpec(g, { net });
        const r = validateSpec(g, card, { resolved });
        for (const s of g?.line?.series || []) if (s.__error) r.errors.push(`recipe: ${s.__error}`);
        results.set(`${id} [${group}]`, r);
      }
      if (cmd === 'dump' && (args.length === 0 || args.includes(id) || args.some((a) => group.startsWith(a)))) {
        console.log(`### ${id} [${group}] ${card.title}`);
        console.log(`DEF: ${card.definition}\nEX: ${card.example}`);
        if (card.claim) console.log(`CLAIM: ${card.claim.claimKind} · ${card.claim.observationPeriod}`);
        console.log(`GRAPHIC: ${stringifySpec(g, '')}\n`);
      }
    }
    if (cmd === 'stats' || cmd === 'check') {
      console.log(`cards ${cards.size}; with graphic ${cards.size - counts.missing.length}; missing ${counts.missing.length}`);
      console.log('by kind', counts.kind);
      console.log('by basis', counts.basis);
    }
    if (cmd === 'check') {
      let errs = report('catalog graphics', results, { quiet: flags.has('--quiet') });
      if (flags.has('--require-all') && counts.missing.length) { console.log(`ERROR missing graphics: ${counts.missing.join(' ')}`); errs++; }
      process.exit(errs ? 1 : 0);
    }
    return;
  }

  console.error('usage: card_graphics.mjs check [--require-all] [--net] | check-fragment <file> | resolve-fragment <file> | merge <file>... | stats | dump [ids]');
  process.exit(2);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
}
