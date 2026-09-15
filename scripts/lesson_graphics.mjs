#!/usr/bin/env node
// EconByte 1.1.5 (Phase 24): story-lesson graphics — checker, fragment merger and
// sources log. Contract: docs/content/LESSON-GRAPHICS-1.1.5.md. It reuses the
// Phase 20 typed graphic spec and its checker (scripts/card_graphics.mjs), with the
// lesson's own prose as the text a `fromLesson` graphic restates, and the story
// validator (scripts/validate_content.mjs courses) for every structural rule.
//
//   node scripts/lesson_graphics.mjs check [--net] [--quiet]
//   node scripts/lesson_graphics.mjs check-fragment <file>... [--net] [--quiet]
//   node scripts/lesson_graphics.mjs resolve-fragment <file>     (fills compute/recipe points; recipes need the network once)
//   node scripts/lesson_graphics.mjs merge <file>...
//   node scripts/lesson_graphics.mjs stats [<catalog.json>]
//   node scripts/lesson_graphics.mjs dump <lessonID|courseID>...
//   node scripts/lesson_graphics.mjs sources-log <out.md> [<fragment>...]   (notes come from the fragments)
//
// Fragment: {"lessons": {"ia-06": {"3": {"visual": {...} | null, "centerpiece": true}}},
//            "notes": {"ia-06/3": "why this picture; evidence"}}
// Beat numbers are 1-based, as in the validator's messages. A merge may change
// only `visual` and `centerpiece` on existing beats; it proves that before writing.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateSpec, resolveSpec, proseNumbers, displayNumbers, displayStrings, computeSeries } from './card_graphics.mjs';
import { validateCourses, lessonText, beatText, isPurposeful, COVERAGE } from './validate_content.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
export const CATALOG = path.join(repo, 'EconByte', 'Resources', 'courses-v1.json');

const readJSON = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const writeCatalog = (f, o) => fs.writeFileSync(f, `${JSON.stringify(o, null, 1)}\n`);
const clean = (o) => JSON.parse(JSON.stringify(o, (k, v) => (k.startsWith('__') ? undefined : v)));

export function lessonsOf(catalog) {
  const out = new Map();
  for (const c of catalog.courses) for (const l of c.lessons) out.set(l.lessonID, { course: c, lesson: l });
  return out;
}

function readFragment(file) {
  const raw = readJSON(file);
  if (!raw || typeof raw.lessons !== 'object') throw new Error(`${file}: a fragment is {"lessons": {...}, "notes": {...}}`);
  return raw;
}

/** Applies fragments to a catalog in place; returns the touched lesson ids. */
export function applyFragments(catalog, fragments) {
  const lessons = lessonsOf(catalog);
  const touched = new Set();
  for (const frag of fragments) {
    for (const [lessonID, beats] of Object.entries(frag.lessons)) {
      const entry = lessons.get(lessonID);
      if (!entry) throw new Error(`unknown lesson ${lessonID}`);
      touched.add(lessonID);
      for (const [n, change] of Object.entries(beats)) {
        if (n.startsWith('_')) continue;
        const beat = entry.lesson.beats[Number(n) - 1];
        if (!Number.isInteger(Number(n)) || !beat) throw new Error(`${lessonID}: no beat ${n}`);
        for (const k of Object.keys(change)) if (!['visual', 'centerpiece'].includes(k)) throw new Error(`${lessonID}/${n}: only visual and centerpiece may change (got ${k})`);
        if ('visual' in change) { if (change.visual === null) delete beat.visual; else beat.visual = change.visual; }
        if ('centerpiece' in change) {
          if (change.centerpiece === true) {
            for (const b of entry.lesson.beats) delete b.centerpiece;
            beat.centerpiece = true;
          } else delete beat.centerpiece;
        }
      }
    }
  }
  return touched;
}

/** Lesson-level checks the story validator does not make: recipes, beat agreement, repeats. */
export async function checkLesson(lesson, { net = false } = {}) {
  const errors = [], warnings = [];
  const hostText = lessonText(lesson);
  let previous = null, run = 0;
  for (const [i, beat] of lesson.beats.entries()) {
    const where = `${lesson.lessonID}/beat ${i + 1}`;
    const key = beat.visual ? JSON.stringify(beat.visual) : null;
    run = key && key === previous ? run + 1 : 1;
    if (key && run === 4) warnings.push(`${where}: the same picture on 4 beats in a row (consider a more specific one)`);
    previous = key;
    if (beat.visual?.type !== 'graphic') continue;
    const g = beat.visual.graphic;
    const resolved = await resolveSpec(g, { net });
    const r = validateSpec(g, null, { host: 'lesson', hostText, resolved });
    for (const s of g?.line?.series || []) if (s.__error) r.errors.push(`recipe: ${s.__error}`);
    errors.push(...r.errors.map((m) => `${where}: ${m}`));
    warnings.push(...r.warnings.map((m) => `${where}: ${m}`));
    // Agreement: a figure the graphic prints should be one this beat (or the one before it) states.
    if (['fromLesson', 'computed'].includes(g.basis)) {
      const near = proseNumbers([beatText(beat), i > 0 ? beatText(lesson.beats[i - 1]) : ''].join(' '));
      const shown = displayStrings(g).flatMap(({ s }) => displayNumbers(s.replace(/\b12-month\b/gi, 'twelve-month')).map((n) => n.v));
      const off = [...new Set(shown.filter((v) => !near.some((a) => Math.abs(a - v) <= Math.max(1e-9, Math.abs(a) * 1e-9) || (Math.abs(a - v) <= 0.051 && !Number.isInteger(v)))))];
      if (off.length) warnings.push(`${where}: prints ${off.join(', ')}, stated elsewhere in the lesson but not on this beat or the one before (review agreement)`);
    }
  }
  return { errors, warnings };
}

export function lessonStats(lesson) {
  const teach = lesson.beats.filter((b) => b.kind === 'idea' || b.kind === 'term');
  const kinds = {}, bases = {}, types = {};
  for (const b of lesson.beats) {
    const t = b.visual?.type ?? 'none';
    if (b.kind === 'idea' || b.kind === 'term') types[t] = (types[t] || 0) + 1;
    if (t === 'graphic') { kinds[b.visual.graphic.kind] = (kinds[b.visual.graphic.kind] || 0) + 1; bases[b.visual.graphic.basis] = (bases[b.visual.graphic.basis] || 0) + 1; }
  }
  return { teach: teach.length, purposeful: teach.filter(isPurposeful).length, types, kinds, bases, centerpiece: lesson.beats.findIndex((b) => b.centerpiece === true) + 1 };
}

function sum(into, from) { for (const [k, v] of Object.entries(from)) into[k] = (into[k] || 0) + v; }

export function catalogStats(catalog) {
  const total = { teach: 0, purposeful: 0, types: {}, kinds: {}, bases: {}, graphics: 0 };
  const perLesson = [];
  for (const { lesson } of lessonsOf(catalog).values()) {
    const s = lessonStats(lesson);
    perLesson.push([lesson.lessonID, s]);
    total.teach += s.teach; total.purposeful += s.purposeful;
    sum(total.types, s.types); sum(total.kinds, s.kinds); sum(total.bases, s.bases);
  }
  total.graphics = Object.values(total.kinds).reduce((a, b) => a + b, 0);
  return { total, perLesson };
}

function printReport(title, { errors, warnings }, quiet) {
  for (const w of quiet ? [] : warnings) console.log(`WARN  ${w}`);
  for (const e of errors) console.log(`FAIL  ${e}`);
  console.log(`${title}: ${errors.length} error(s), ${warnings.length} warning(s)`);
}

async function checkCatalog(catalog, { lessonIDs = null, net = false, fragment = false } = {}) {
  const tmp = path.join(os.tmpdir(), `econbyte-lesson-graphics-${process.pid}.json`);
  writeCatalog(tmp, catalog);
  const rep = validateCourses(tmp, { fragment: false });
  fs.rmSync(tmp, { force: true });
  let errors = rep.errors, warnings = rep.warnings;
  if (lessonIDs) {
    // A fragment is judged on its own lessons; catalog-wide coverage is judged at merge.
    const mine = (m) => [...lessonIDs].some((id) => m.includes(`lesson ${id}`));
    errors = errors.filter(mine); warnings = warnings.filter(mine);
  }
  for (const { lesson } of lessonsOf(catalog).values()) {
    if (lessonIDs && !lessonIDs.has(lesson.lessonID)) continue;
    const r = await checkLesson(lesson, { net });
    errors = errors.concat(r.errors); warnings = warnings.concat(r.warnings);
  }
  return { errors, warnings, stats: rep.stats };
}

function describeVisual(v) {
  if (!v) return '—';
  switch (v.type) {
    case 'graphic': return `graphic ${v.graphic.kind}/${v.graphic.basis}: ${v.graphic.title}`;
    case 'diagram': return `diagram ${v.diagramID}`;
    case 'chart': return `chart ${v.chartID}`;
    case 'symbol': return `symbol ${v.name}`;
    case 'stat': return `stat ${v.value} (${v.label})`;
    case 'flow': return `flow ${v.steps.join(' → ')}`;
    case 'compare': return `compare ${v.left.label} | ${v.right.label}`;
    default: return v.type;
  }
}

function sourceFor(lesson, g) {
  switch (g.basis) {
    case 'sourced': return `${g.source.organization}, "${g.source.title}", ${g.source.url}, ${g.source.period}, retrieved ${g.source.retrieved}; series ${(g.line?.series || []).map((s) => s.recipe?.series || s.recipe?.indicator).join(', ')}`;
    case 'computed': return `Computed: ${(g.line?.series || []).map((s) => `${s.name} = ${JSON.stringify(s.compute)}`).join('; ')} (inputs stated in the lesson; lesson sources: ${lesson.sources.map((s) => s.organization).join('; ')})`;
    case 'fromLesson': return `Restates the lesson's figures (lesson sources: ${[...new Set(lesson.sources.map((s) => s.organization))].join('; ')})${g.derived ? `; derived ${g.derived.map((d) => `${d.value} = ${d.expr}`).join(', ')}` : ''}`;
    case 'illustrative': return 'Illustrative, not real data (labelled in the app)';
    case 'conceptual': return 'Conceptual (no numbers)';
    default: return g.basis;
  }
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const flags = new Set(rest.filter((a) => a.startsWith('--')));
  const args = rest.filter((a) => !a.startsWith('--'));
  const net = flags.has('--net'), quiet = flags.has('--quiet');

  if (cmd === 'check') {
    const catalog = readJSON(CATALOG);
    const r = await checkCatalog(catalog, { net });
    const { total } = catalogStats(catalog);
    console.log(`coverage: ${total.purposeful}/${total.teach} teaching beats (${(100 * total.purposeful / total.teach).toFixed(1)}%); graphics ${total.graphics}`);
    console.log('by visual type', total.types); console.log('graphics by kind', total.kinds); console.log('graphics by basis', total.bases);
    printReport('lesson graphics', r, quiet);
    process.exit(r.errors.length ? 1 : 0);
  }
  if (cmd === 'check-fragment') {
    const catalog = readJSON(CATALOG);
    const touched = applyFragments(catalog, args.map(readFragment));
    const r = await checkCatalog(catalog, { lessonIDs: touched, net });
    for (const id of touched) {
      const s = lessonStats(lessonsOf(catalog).get(id).lesson);
      console.log(`${id}: ${s.purposeful}/${s.teach} purposeful, centerpiece beat ${s.centerpiece || 'NONE'}, graphics ${JSON.stringify(s.kinds)}`);
    }
    printReport(args.join(', '), r, quiet);
    process.exit(r.errors.length ? 1 : 0);
  }
  if (cmd === 'resolve-fragment') {
    const file = args[0];
    const frag = readFragment(file);
    for (const beats of Object.values(frag.lessons)) for (const change of Object.values(beats)) {
      const g = change?.visual?.type === 'graphic' ? change.visual.graphic : null;
      if (!g) continue;
      await resolveSpec(g, { net: true, write: true });
      for (const s of g.line?.series || []) if (s.__error) console.log(`recipe error: ${g.title}: ${s.__error}`);
    }
    fs.writeFileSync(file, `${JSON.stringify(clean(frag), null, 2)}\n`);
    console.log(`resolved ${file}`);
    return;
  }
  if (cmd === 'merge') {
    const before = readJSON(CATALOG);
    const catalog = readJSON(CATALOG);
    const fragments = args.map(readFragment);
    applyFragments(catalog, fragments);
    for (const { lesson } of lessonsOf(catalog).values()) for (const b of lesson.beats) {
      if (b.visual?.type === 'graphic') await resolveSpec(b.visual.graphic, { net: false, write: true });
    }
    const out = clean(catalog);
    const strip = (o) => JSON.stringify(o, (k, v) => (k === 'visual' || k === 'centerpiece' ? undefined : v));
    if (strip(before) !== strip(out)) throw new Error('merge: the catalog changed outside visual/centerpiece fields');
    const r = await checkCatalog(out, {});
    printReport('merged catalog', r, true);
    if (r.errors.length) { console.log('merge aborted: fix the errors above'); process.exit(1); }
    writeCatalog(CATALOG, out);
    const { total } = catalogStats(out);
    console.log(`wrote ${CATALOG}: coverage ${total.purposeful}/${total.teach}, graphics ${total.graphics}`);
    return;
  }
  if (cmd === 'stats') {
    const catalog = readJSON(args[0] ?? CATALOG);
    const { total, perLesson } = catalogStats(catalog);
    for (const [id, s] of perLesson) console.log(`${id.padEnd(7)} ${String(s.purposeful).padStart(2)}/${s.teach} centerpiece ${s.centerpiece || '-'} ${JSON.stringify(s.types)}`);
    console.log(JSON.stringify(total, null, 1));
    return;
  }
  if (cmd === 'dump') {
    const catalog = readJSON(CATALOG);
    for (const { course, lesson } of lessonsOf(catalog).values()) {
      if (!args.includes(lesson.lessonID) && !args.includes(course.courseID)) continue;
      console.log(`\n## ${lesson.lessonID} ${lesson.title} — ${lesson.summary}`);
      for (const c of lesson.charts) console.log(`   [chart ${c.chartID} ${c.kind}] ${c.title} — ${c.caption}`);
      lesson.beats.forEach((b, i) => {
        const text = [b.heading && `«${b.heading}»`, b.text, ...(b.terms || []).map((t) => `${t.term}: ${t.definition}`), b.check && `Q: ${b.check.question} [${b.check.choices.join(' | ')}] → ${b.check.choices[b.check.answerIndex]}. ${b.check.explanation}`, ...(b.items || [])].filter(Boolean).join(' ');
        console.log(`${String(i + 1).padStart(2)} ${b.kind.padEnd(5)}${b.centerpiece ? '★' : ' '}${b.tone ? `(${b.tone}) ` : ''}${text}\n      visual: ${describeVisual(b.visual)}`);
      });
      console.log(`   sources: ${lesson.sources.map((s) => `${s.organization} — ${s.documentTitle}`).join(' | ')}`);
    }
    return;
  }
  if (cmd === 'sources-log') {
    const [outFile, ...fragFiles] = args;
    const catalog = readJSON(CATALOG);
    const notes = Object.assign({}, ...fragFiles.map((f) => readFragment(f).notes || {}));
    const lines = [];
    for (const { lesson } of lessonsOf(catalog).values()) {
      lines.push(`\n### ${lesson.lessonID} — ${lesson.title}\n`);
      lines.push('| Beat | Graphic | Basis and source | Review note |', '|---|---|---|---|');
      lesson.beats.forEach((b, i) => {
        if (b.visual?.type !== 'graphic') return;
        const g = b.visual.graphic;
        const cell = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
        lines.push(`| ${i + 1}${b.centerpiece ? ' ★' : ''} | ${cell(g.kind)}: ${cell(g.title)} | ${cell(g.basis)}. ${cell(sourceFor(lesson, g))} | ${cell(notes[`${lesson.lessonID}/${i + 1}`])} |`);
      });
    }
    fs.writeFileSync(outFile, lines.join('\n') + '\n');
    console.log(`wrote ${outFile}`);
    return;
  }
  console.error('usage: lesson_graphics.mjs check | check-fragment <f>... | resolve-fragment <f> | merge <f>... | stats [catalog] | dump <id>... | sources-log <out.md> [fragments]');
  process.exit(2);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
}
