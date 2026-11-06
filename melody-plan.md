# Plan: jianpu melody lines in nns charts

Implements a v1 of *Spec: Jianpu + Nashville Melody Notation for Chart
Generator* (Nov 6, 2026) inside the existing LuaLaTeX pipeline. Decisions
below were made with the spec author; where they differ from the spec, the
decision wins.

## Decisions

| Topic | Decision |
|---|---|
| Engine | Native Lua + TikZ, next to `nns.lua`. No LilyPond, Python or shell-escape. (A jianpu-ly + LilyPond comparison was prototyped and rejected: better spacing, but plain-text chords, its own key/time furniture, and a heavy toolchain.) |
| Where melodies live | Inside song `.tex` files, as `\melody{...}` inside a `section`. |
| Relation to chord bars | A section with `\melody` shows the melody only; its chords come from the melody's `[chord]` tokens. `\bars` and `\melody` in the same section is an error. |
| Outputs | PDF only. The spec's monospace text renderer and SVG are deferred. |
| Unit of a bare note | One unit of the time signature's denominator: a quarter in 4/4, an eighth in 6/8. `/` and `//` halve and quarter that unit; underlines are relative to it. |
| Sections and repeats | Reuse chart sections; the melody syntax accepts `\|:` `:\|` `\|\|` and `[1.` `[2.` endings exactly as `\bars` does. |
| Spacing | Fixed beat grid (every beat the same width, so voices and chords align exactly), tightened: narrower hold dashes, a minimum gap inside beamed groups, room reserved for accidentals. |
| Lyrics | Not in v1. |
| Voice default octave | Not supported; every low or high note carries its own `,` or `'`. |

## Input

```latex
\begin{section}{Chorus}
  \melody{ [4add2] 2/ 2/ 1/ 1/ 3/ 3/ [6m] 1/ 1/ | [5add4] 2/ 2/ 1/ 1/ 7,/ 7,/ 1/ 1/ || }
\end{section}

\begin{section}{Tag}
  \melody{
    S: [1] (1 3 5) - - - | [5] (2 5 7) - - - ||
    B:     1, 5, 1 -     |     5, - 5, -     ||
  }
\end{section}
```

- Note, rest, hold, tie, stack and bar syntax follow the spec's grammar.
- **Chord symbols use the existing `\bars` chord grammar** (`4add2`, `5sus`,
  `1/3`, `b7`, `2m7`, ...), parsed by the same `parse_chord` and drawn by the
  same `chord_tex`, so melody chords look identical to chart chords. This is a
  superset of the spec's chord table. Bar-level marks (push, diamond, beat
  ticks) are not accepted inside `[...]` in v1.
- **Voices** start with `Name:`. TeX turns line breaks into spaces, so voices
  are split on these labels rather than on newlines. When the first voice's
  label appears again, the input continues that voice; input "systems" do not
  affect layout, which breaks lines by bar count.
- A melody with no `Name:` is a single unnamed voice and gets no label gutter.
- `repeatchords` (default true) is an `\nnsset` key; when false, a chord equal
  to the previous one is not drawn.

## Architecture

```
src/lua/nns.lua        exports parse_chord, chord_tex, report, key/time state
src/lua/nnsmelody.lua  NEW: lexer -> parser -> validator -> layout -> TikZ emitter
src/tex/nnschart.cls   \melody command, jianpu fonts and TikZ styles
tests/melody_test.lua  NEW: texlua unit tests (parser, validator, layout)
```

Pipeline in `nnsmelody.lua`, each stage a plain function so tests can call it
without TeX:

1. **lex(src)**: tokens with source column, for error messages.
2. **parse(tokens, time)**: voices -> bars -> events (note, rest, stack), holds
   folded into the previous event, ties flagged, chords pinned to the start
   beat of the next event. Durations are in units of the time signature's
   denominator.
3. **validate(tree, time)**: the spec's error and warning table (bar sums per
   voice, equal bar counts across voices, trailing chord, two chords on one
   beat, dotted note followed by `-`, `-` with no note, more than two octave
   marks, tie between different pitches, duplicate pitch in a stack). Errors
   use the same `tex.error` path as `\bars`, naming section, bar and voice.
4. **layout(tree, width)**: pure function returning positioned boxes: x per
   event from its start beat, row y per voice from stack height and dot or
   underline depth, chord positions, bar lines, ending brackets, tie arcs and
   beam spans, broken into rows at bar boundaries.
5. **emit(layout)**: TikZ, in the same `out()` style as `nns.lua`.

## Layout rules

- **Beat width** = available width / (bars per row x beats per bar), clamped
  to a minimum (about 22pt at the jianpu digit size). If the minimum doesn't
  fit, bars per row drops until it does. Bars per row starts from
  `barsperrow`. In the default two-column layout this means about 2 bars of
  4/4 per row, which needs checking on real charts.
- **Digits**: the chord font's tabular digits at about 16pt; equal advance
  keeps voices aligned.
- **Octave dots**: above the top digit of an event; below the lowest digit,
  under its underlines.
- **Underlines**: one per `/` level, merged across consecutive notes in the
  same beat; two levels for `//`.
- **Augmentation dot**: right of the digit. **Holds**: one short dash per
  extra unit. **Ties**: arcs above, allowed to cross bar lines and row
  breaks (split into two half arcs at a break).
- **Accidentals**: Bravura flat or sharp, left of the digit, with space
  reserved in the grid.
- **Stacks**: digits stacked upward from the lowest; length marks only on the
  lowest.
- **Chords**: one row above the top voice, left-aligned with their event, in
  `\nnsChordFont` at a smaller size.
- **Bar lines** span all voices; repeat signs and ending brackets reuse the
  `\bars` drawing styles.

## Testing

- **Unit tests** (`texlua tests/melody_test.lua`, run by a new `make test`):
  parse every spec example; check event beats, chord beats, and every
  validation row (one passing and one failing input each); check that layout
  gives events starting on the same beat the same x in every voice (spec
  acceptance 5); and check that a chord written on any voice renders once,
  above the top voice (spec acceptance 6).
- **Real songs**: the guitar tab in `songs/holy-forever.tex` and
  `songs/front-porch.tex` is rewritten as `\melody` lines (no separate demo
  song). Spec examples 1 to 5, a 6/8 line and endings were checked by eye in
  a scratch document.
- **Regression**: every existing song still builds unchanged.

## Milestones

1. Export the shared chord and report helpers from `nns.lua`; add the
   `\melody` command and an empty `nnsmelody.lua`.
2. Parser and validator for single-voice melodies, with unit tests.
3. Layout and emitter for single voice: digits, octaves, underlines, dots,
   holds, rests, accidentals, chords, bar lines, row breaks.
4. Ties, repeats and endings.
5. Multiple voices and stacks.
6. 6/8 and other denominators; `repeatchords`.
7. Tab in existing songs rewritten as melodies, README section, `make test`.

## Out of scope for v1

Text renderer, SVG, lyrics, voice default octaves, tuplets, grace notes,
proportional spacing, letter-name or MIDI resolvers, ABC or MusicXML import.

## Spec items this plan changes

- The bare-note unit is the time signature's denominator, not always a beat.
- Chord symbols use the repo's existing chord grammar.
- Voices are separated by `Name:` labels, not by lines and blank lines.
- The text renderer and its golden-output acceptance criteria (spec
  acceptance 1 and 2) move to a later version; v1 verifies with parser and
  layout unit tests plus visual checks.
