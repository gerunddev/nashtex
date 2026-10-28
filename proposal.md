# Proposal: `nns`, a Nashville Number System chart builder (LaTeX, CLI, macOS)

## 1. Goal

A git repo that holds Nashville number charts as plain-text LaTeX source and builds them into PDFs with one command:

```
make pdf name-of-song     # -> build/name-of-song.pdf
```

Scope is **Nashville charts only**: no lyrics, no tablature. The tool is macOS-only. All dependencies are installed by `make install` via Homebrew and resolved locally by the CLI, so nothing depends on the user's global TeX setup.

## 2. Non-goals

- Lyrics, chord-over-lyric sheets, tablature, standard notation.
- Linux or Windows support.
- A GUI or browser editor.
- Installing the full MacTeX distribution.

## 3. Repository layout

```
.
├── Makefile
├── Brewfile                 # brew dependencies
├── README.md                # short usage doc (derived from this file)
├── .gitignore               # build/, .texmf/
├── src/
│   ├── bin/nns              # bash CLI: build, new, list, clean, doctor
│   ├── tex/nnschart.cls     # LaTeX class: page layout, grid, drawing macros
│   ├── lua/nns.lua          # bar-string parser + marks table (LuaLaTeX)
│   └── fonts/               # Bravura.otf (SIL OFL) + license file, committed
├── songs/
│   └── name-of-song.tex     # one file per song
└── build/                   # latexmk output (gitignored)
```

## 4. User-facing commands

| Command | Behavior |
|---|---|
| `make install` | `brew bundle`, then install local TeX packages into `.texmf/` (see §5) |
| `make pdf <song>` | Build `songs/<song>.tex` to `build/<song>.pdf`; print the output path |
| `make pdf` | Build every song in `songs/` |
| `make pdf SONG=<song>` | Equivalent to the positional form |
| `make build/<song>.pdf` | Real file rule (`build/%.pdf: songs/%.tex`), so incremental rebuilds work |
| `make clean` | Remove `build/` |
| `make doctor` | Print resolved tool paths and versions; non-zero exit if anything is missing |
| `make new <song>` | Scaffold `songs/<song>.tex` from a template |
| `make list` | List songs in `songs/` |

The Makefile is a thin wrapper. All logic lives in `src/bin/nns` (`nns build <song>`, `nns new <song>`, `nns doctor`, and so on), so the tool also works without make.

**Positional-argument trick:** `make pdf name-of-song` works by reading `$(MAKECMDGOALS)`, taking the word after `pdf` as the song name, and defining a no-op catch-all rule (`%: ; @:`) so make does not error on the song name. Songs named like existing targets (`pdf`, `clean`, `install`) are rejected with a clear error.

## 5. Dependencies and local resolution

**Brewfile**
- `cask "basictex"` (about 100 MB, includes LuaLaTeX)
- `brew "latexmk"` (if not already bundled by BasicTeX)

**Project-local TeX packages.** `make install` runs `tlmgr --usermode` with `TEXMFHOME=$PWD/.texmf` to install the extra packages the class needs (at minimum `tabularray`, `fontspec`, `tikz`/`pgf`, `xcolor`, `geometry`, `luacode`; the build agent should verify the exact list by building). Nothing is installed globally beyond BasicTeX.

**Font.** Bravura (SIL OFL) is committed under `src/fonts/` and loaded by path via `fontspec` (`Path=`), so there is no cask and no system font install. Include the OFL license text.

**Explicit tool resolution.** `nns` resolves tools once at startup, in this order:
1. `/Library/TeX/texbin` (BasicTeX)
2. `$(brew --prefix)/bin`
3. `PATH`

It exports:
- `TEXMFHOME=<repo>/.texmf`
- `TEXINPUTS=<repo>/src/tex:`
- `LUAINPUTS=<repo>/src/lua:`
- `OSFONTDIR=<repo>/src/fonts`

so `\documentclass{nnschart}` works with nothing installed globally.

`nns doctor` prints each resolved path and version (lualatex, latexmk, tlmgr, brew) and fails with an actionable message ("run `make install`") if one is missing.

## 6. Song file format

Each song is a normal `.tex` file using the `nnschart` class:

```latex
\documentclass{nnschart}
\songinfo{title={Name of Song}, key=G, tempo=92, time=4/4}
\begin{document}
\begin{section}{Verse}
  \bars{ | 1 | 4 . 5 | <6m | 4 | }
\end{section}
\begin{section}{Chorus}
  \bars{ | 1 | <4 | 5 | <1* | }
\end{section}
\end{document}
```

`\bars{...}` hands its argument to Lua (`nns.lua`), which parses the bar string and emits TikZ/`tabularray` code. The grid is configurable (bars per row, default 4).

## 7. Notation to support

| Mark | Input syntax | Rendering |
|---|---|---|
| Chord | `1 4 5 6m 7° 5/7` | Number, quality, optional slash bass |
| Quality (minor, dim, 7, maj7, sus, add) | `6m`, `7°`, `1maj7`, `4sus`, `1add9` | Superscript/suffix per NNS convention |
| Accidentals | `b3`, `#4` | Bravura flat/sharp glyphs |
| Push / anticipation | `<6m` | `<` before the chord |
| Diamond (held whole note) | `1*` (also `\diamond`) | Diamond around the chord |
| Two chords in one bar | `4 . 5` or `[4 5]` | Chords side by side with underline or bracket |
| Beat ticks | `1 / / /` | Hash marks for beat distribution |
| Rest | `r` | Rest glyph |
| Stop / accent | `!`, `^` | Stop and accent marks |
| Mute triangle | `\mute` | Triangle |
| Repeats | `\|:` `:\|` | Standard repeat bars |
| Endings | `[1.` `[2.` | First and second ending brackets |
| Section label | `\begin{section}{Verse}` | Boxed label |
| Key change | `\keychange{A}` | Marker showing the new key |

The marks live in `nns.lua` as a plain data table (token pattern → drawing function), so adding a mark is one table entry plus one TikZ snippet.

**Parser rules (spec for the agent):**
- Bars are separated by `|`. Whitespace is insignificant except as a token separator.
- A bar with two chords separated by `.` or wrapped in `[ ]` is a split bar.
- Unknown tokens raise a TeX error that names the offending token, the bar number, and the section.
- Chords are parsed into structured data (degree, accidental, quality, bass) before rendering, which also leaves room for transposition later.

## 8. Build pipeline

1. `nns build <song>` validates that `songs/<song>.tex` exists and that `nns doctor` passes.
2. It runs `latexmk -lualatex -interaction=nonstopmode -outdir=build songs/<song>.tex` with the environment from §5.
3. On success, it prints `build/<song>.pdf`. On failure, it prints the relevant lines of the log and exits non-zero.

## 9. Milestones and acceptance criteria

1. **Skeleton.** Brewfile, `make install`, `nns doctor`, Makefile with the positional trick, and a hello-world song.
   *Accept:* on a clean Mac, `make install && make pdf hello` produces `build/hello.pdf`.
2. **Core grid.** Bars, bars-per-row, section labels, chords with qualities, slash chords, and accidentals.
   *Accept:* a sample song with these renders correctly; `make doctor` passes.
3. **Marks.** Push, diamond, ticks, underline/bracket, rests, stop/accent, and mute.
   *Accept:* a `songs/_marks-demo.tex` exercising every mark builds cleanly and looks right.
4. **Structure.** Repeats, endings, key changes, `make new`, and `make list`.
   *Accept:* a song with repeats and two endings renders correctly; `make new foo` creates a buildable file.
5. **Extras (optional).** A combined book PDF of all songs, a `--letters` flag that renders chord names for a given key, and CI that runs `make doctor`.

## 10. Open decisions for the implementer

- **Page layout:** the default is one song per page. Letter vs A4 is configurable, defaulting to Letter.
- **Parser language:** Lua inside LuaLaTeX keeps everything in one toolchain. If it proves painful, fall back to a bash/awk preprocessor that emits TeX before `latexmk`.
- **tlmgr user mode on BasicTeX:** if per-repo `TEXMFHOME` installs prove flaky, fall back to `sudo tlmgr install` in `make install` and document it.
- **Tablature (future):** not in scope now. If added later, `brew install lilypond` plus `lyluatex` fits this structure without changes.

## 11. References

- CTAN music topic: https://ctan.org/topic/music
- latex4musicians guide: https://ctan.math.washington.edu/tex-archive/info/latex4musicians/latex4musicians.pdf
- Mark-set references (non-LaTeX): 1Chart and the browser-based Nashville Chart Builder, useful as checklists for notation coverage.
