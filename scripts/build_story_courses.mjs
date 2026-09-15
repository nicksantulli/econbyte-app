#!/usr/bin/env node
// EconByte 1.1.5 story lessons: assemble courses-v1.json (schemaVersion 2).
//
//   node scripts/build_story_courses.mjs fragment <course.json> <out-catalog.json>
//       Wraps ONE converted course (a course object whose lessons carry `charts`
//       and `beats`) in a catalog, fills every estimatedMinutes, and writes a
//       fragment catalog that `validate_content.mjs courses <file> --fragment`
//       accepts. Writers use it to check their own course.
//
//   node scripts/build_story_courses.mjs assemble <dir>
//       Reads <dir>/investing-approaches.json, reading-price-charts.json and
//       bonds-rates-yield-curve.json, fills minutes, and writes
//       EconByte/Resources/courses-v1.json.
//
// Minutes are computed, never typed: the words a reader sees (cover summary,
// every beat, every check explanation) at 170 words per minute, plus 20 seconds
// per check, rounded up, minimum 2. A course's minutes are the sum of its
// lessons. JSON is built here, in Node, never with shell strings.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { beatWords, wordCount, EXPECTED_COURSES } from './validate_content.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const resource = path.join(repo, 'EconByte', 'Resources', 'courses-v1.json');

export const CATALOG_META = {
  schemaVersion: 2,
  catalogVersion: '1.1.5-stories-1',
  verifiedOn: '2026-09-14',
  disclaimer: 'Educational content only. EconByte does not provide financial, investment, or tax advice.',
  educationalNotice: 'Educational content only — not investment advice. Nothing here recommends any investment or predicts any price.',
  editorialPolicy: 'Every lesson cites public primary sources (SEC/investor.gov, FINRA, Federal Reserve and Reserve Banks, Treasury and TreasuryDirect, NBER) with canonical https URLs re-verified on 2026-09-14. Lessons are told as short story beats, one idea per screen; the 1.1.5 conversion kept every fact of the audited 1.1.4 lessons. Charts plot clearly labeled synthetic series designed to show a mechanism; no real market data is shown anywhere.',
};

export function lessonMinutes(lesson) {
  const beats = lesson.beats ?? [];
  const checks = beats.filter(b => b.kind === 'check');
  const words = wordCount(lesson.summary)
    + beats.reduce((n, b) => n + beatWords(b), 0)
    + checks.reduce((n, b) => n + wordCount(b.check?.explanation), 0);
  return Math.max(2, Math.ceil(words / 170 + checks.length * (20 / 60)));
}

/** Key order matters for readable diffs: lesson fields in schema order. */
function normalizeCourse(course) {
  const lessons = (course.lessons ?? []).map(lesson => ({
    lessonID: lesson.lessonID,
    title: lesson.title,
    summary: lesson.summary,
    estimatedMinutes: lessonMinutes(lesson),
    isPreview: lesson.isPreview,
    charts: lesson.charts ?? [],
    beats: lesson.beats ?? [],
    sources: lesson.sources ?? [],
  }));
  return {
    courseID: course.courseID,
    title: course.title,
    icon: course.icon,
    summary: course.summary,
    level: course.level,
    estimatedMinutes: lessons.reduce((n, l) => n + l.estimatedMinutes, 0),
    lessons,
  };
}

function write(file, object) {
  fs.writeFileSync(file, `${JSON.stringify(object, null, 1)}\n`);
}

function main() {
  const [mode, a, b] = process.argv.slice(2);
  if (mode === 'fragment' && a && b) {
    const course = JSON.parse(fs.readFileSync(a, 'utf8'));
    write(b, { ...CATALOG_META, courses: [normalizeCourse(course)] });
    console.log(`wrote ${b}`);
  } else if (mode === 'assemble' && a) {
    const courses = EXPECTED_COURSES.map(([id]) => normalizeCourse(JSON.parse(fs.readFileSync(path.join(a, `${id}.json`), 'utf8'))));
    write(resource, { ...CATALOG_META, courses });
    console.log(`wrote ${resource}: ${courses.map(c => `${c.courseID} ${c.lessons.length} lessons ${c.estimatedMinutes} min`).join('; ')}`);
  } else {
    console.error('usage: build_story_courses.mjs fragment <course.json> <out.json> | assemble <dir>');
    process.exit(2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main();
