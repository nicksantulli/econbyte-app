# EconByte 1.1.5 — story lessons (courses-v1.json schemaVersion 2)

Owner, 2026-09-15: "I want all lessons to be almost like a 'story' you click through rather than an article you read."

A lesson is no longer an ordered list of article blocks. It is an ordered list of **beats**: one idea per
screen, tapped (or swiped) through like a phone story, with a segmented progress bar at the top. The app draws a
cover page (course name, lesson title, `summary`, minutes) before the first beat, so beats never repeat the title.

## Lesson

```json
{
  "lessonID": "ia-01",
  "title": "Risk and Return",
  "summary": "≤ 35 words",
  "estimatedMinutes": 3,
  "isPreview": true,
  "charts": [ ChartSpec, … ],
  "beats": [ Beat, … ],
  "sources": [ … unchanged … ]
}
```

- `charts` holds the lesson's synthetic charts exactly as 1.1.4 shipped them (`chartID`, `kind`, `title`,
  `caption`, `dataNote`, axis labels, `series`/`candles`, `markers`). The `caption` is no longer printed under the
  chart; it stays as the chart's VoiceOver description, so every fact it states must also be said by a beat.
- `blocks` is gone. A lesson that still carries `blocks` fails validation (no stale second copy of the content).
- `estimatedMinutes` is recomputed by `scripts/build_story_courses.mjs` from the words a reader sees
  (≈ 170 words per minute plus 20 s per check, rounded up, minimum 2); a course's minutes are the sum of its lessons.

## Beat

| field | kinds | rule |
|---|---|---|
| `kind` | all | `idea` · `term` · `check` · `recap` |
| `heading` | idea, term | optional, ≤ 8 words |
| `text` | idea (required), term (optional) | the beat's one idea |
| `tone` | idea | optional `note` · `caution` · `example` (the old callout styles) |
| `terms` | term | 1–2 `{term, definition}` |
| `check` | check | `{question, choices (3–4, unique), answerIndex, explanation}` |
| `items` | recap | 2–5 short lines |
| `visual` | idea, term, check | optional, see below |

**Word limit: 35 per beat.** Counted words (whitespace-separated) are everything the reader reads on that screen:
`heading` + `text` + every term and definition + recap `items` + the visual's own words (`stat` value and label,
`flow` steps, `compare` labels and details). A `check` counts `question` + all `choices` (≤ 35), and its
`explanation`, which replaces nothing but is revealed after answering, is limited separately (≤ 35). Chart and
diagram artwork labels are not counted (they are fixed drawings, not reading).

## Visual

```json
{"type": "diagram", "diagramID": "risk-return-ladder"}
{"type": "chart",   "chartID": "ia-01-two-paths"}
{"type": "stat",    "value": "7%", "label": "yearly return, illustrative"}
{"type": "flow",    "steps": ["Income", "Price change", "Total return"]}
{"type": "compare", "left": {"label": "Steady", "detail": "small swings"}, "right": {"label": "Volatile", "detail": "wide swings"}}
{"type": "symbol",  "name": "scalemass.fill"}
```

- `diagram`: one of the 14 drawings in `DiagramView` (same ids as 1.1.4). A diagram or chart may appear on more
  than one beat (e.g. two beats that explain the same picture).
- `chart`: the `chartID` of a chart in this lesson's `charts`. Every chart in `charts` must be shown by some beat.
- `stat`: `value` ≤ 16 characters, `label` ≤ 6 words. A number shown here must be stated in the lesson (no new
  figures).
- `flow`: 2–4 steps, ≤ 4 words each, drawn as boxes joined by arrows.
- `compare`: two sides, `label` ≤ 4 words, `detail` ≤ 8 words.
- `symbol`: an SF Symbol from the allowlist in `StoryVisual.allowedSymbols` / `ALLOWED_SYMBOLS`. Decorative:
  at most a third of a lesson's visual beats may be symbols.

## Lesson rules (Swift `CourseCatalog.validate` and `scripts/validate_content.mjs courses`)

- 10–30 beats; the first beat is an `idea` or a `term`.
- Exactly one `recap`, and it is the last beat.
- 1–2 `check` beats, never first or last.
- More than half of all beats carry a `visual`.
- Every word limit above; every text passes the editorial prose checks (no advice, predictions, named
  securities/brands, stale temporal words, future years).
- Every diagram the app can draw is used by some lesson.

## Progress (CourseProgressStore)

UserDefaults key `econ.courses.progress` keeps its 1.1.4 shape and gains optional fields, so a 1.1.4 record
decodes unchanged:

```json
{"ia-01": {"completedAt": 780000000, "quizCorrect": true, "lastBeat": 4, "checks": {"0": true, "1": false}}}
```

- `completedAt` / `quizCorrect` are kept exactly (completion and the first quiz answer carry over).
- `lastBeat` is the story page to resume at (0 = cover); cleared when the lesson completes.
- `checks` records the first answer to each check by its order in the lesson. The first check's answer is also
  `quizCorrect`, so a 1.1.4 quiz answer shows as the first check's verdict.
- `econ.courses.progress.version` = 2 after the one-time migration, which drops a `lastBeat` beyond a lesson's
  page count.
