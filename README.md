# nns: Nashville Number System charts

Nashville number charts as plain-text LaTeX, built to PDF with one command:

```
make pdf name-of-song     # -> build/name-of-song.pdf
```

Nashville charts only (no lyrics, no tablature). macOS only.

## Setup

```
make install    # brew bundle (BasicTeX) + project-local TeX bits in .texmf/
make doctor     # shows resolved tools; non-zero exit if anything is missing
```

Installing the BasicTeX cask asks for your password once. Everything else lives
in the repo: extra TeX packages and latexmk go in `.texmf/` (latexmk isn't in
Homebrew and `tlmgr --usermode` refuses it, so it is fetched from CTAN as a
single script), and font caches go in `.texmf-var/`. Bravura (SIL OFL, see
`src/fonts/OFL.txt`) is committed and loaded by path.

## Commands

| Command | Behavior |
|---|---|
| `make pdf <song>` | Build `songs/<song>.tex` to `build/<song>.pdf` |
| `make pdf` | Build every song |
| `make pdf SONG=<song>` | Same as the positional form |
| `make pdf <song> LETTERS=1` | Render chord letters for the song's key -> `build/<song>-letters.pdf` |
| `make build/<song>.pdf` | Incremental file rule |
| `make book` | Bind all songs (except `_*` demos) into `build/book.pdf` |
| `make new <song>` | Scaffold `songs/<song>.tex` |
| `make list` | List songs |
| `make clean` | Remove `build/` |
| `make doctor` / `make install` | See above |

The Makefile is a thin wrapper; `src/bin/nns` does the work and can be run
directly (`src/bin/nns build hello`, `src/bin/nns help`).

## Song format

```latex
\documentclass{nnschart}          % options: a4 (default Letter), onecolumn
\songinfo{title={Name of Song}, key=G, tempo=92, time=4/4}
\begin{document}
\begin{section}{Verse}
  \bars{ | 1 | 4 . 5 | <6m | 4 | }
\end{section}
\keychange{A}
\begin{section}{Chorus}
  \bars{ |: 1 | <4 | [1. 5 | 1* :|[2. 5 | 1 || }
\end{section}
\end{document}
```

There are no measure lines: each chord is a measure, measures are spaced like
words, and chords that share a measure sit closer together and are
underlined. Each line holds `barsperrow` measures (default 4).

`\songinfo` also takes `artist=` (shown in the footer), `feel=`, and `book=`
(a songbook name for the running head). `\nnsset{barsperrow=N}` changes
the number of measures per line for the whole song.

## Notation

| Mark | Input | Notes |
|---|---|---|
| Chord | `1 4 5 6m 7° 5/7` | `-` also means minor; `dim` renders as ° |
| Qualities | `1maj7 4sus 1add9 2m7 7m7b5 5sus4 1Δ7 7ø` | Superscripted |
| Accidentals | `b3 #4 1/b7` | Bravura glyphs |
| Push | `<6m` | |
| Diamond | `1*` or `1 \diamond` | |
| Split bar | `4 . 5` or `4 5` (underlined), `[4 5]` (bracketed) | `1 [4 5]` brackets part of a bar |
| Beat ticks | `1 / / /` | |
| Rest | `r` | |
| Stop / accent | `5!` or `5 !`, `4^` or `4 ^` | |
| Mute | `1 \mute` | Triangle above the chord |
| Measures | `\|` separates measures and is not drawn; `\|\|` `\|:` `:\|` `:\|:` draw double bars and repeats | |
| Endings | `[1.` `[2.` right after a barline | Ends at `:\|`, `\|\|`, the next ending, or the end of the string |
| Section | `\begin{section}{Verse}` | |
| Key change | `\keychange{A}` | |

Unknown tokens stop the build with an error naming the token, the bar number
and the section. Marks are a data table in `src/lua/nns.lua` (`M.marks`):
adding one is a table entry plus, usually, a TikZ style in
`src/tex/nnschart.cls`. Set `NNS_DEBUG=1` to echo the generated TikZ into the
log.

`songs/_marks-demo.tex` and `songs/_structure-demo.tex` exercise everything.

## Layout

```
Makefile, Brewfile
src/bin/nns            bash CLI
src/tex/nnschart.cls   page layout, header, sections, drawing styles
src/lua/nns.lua        bar-string lexer/parser, marks table, grid renderer
src/fonts/             Bravura.otf + OFL.txt
songs/                 one .tex per song
build/                 output (gitignored)
```
