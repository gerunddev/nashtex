% nnschart.cls: Nashville Number System charts for LuaLaTeX.
%
% Page layout, header, sections and drawing styles live here; parsing and
% grid layout of \bars{...} live in nns.lua.
\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{nnschart}[2026/10/28 v0.1 Nashville Number System charts]

\ifdefined\directlua\else
  \ClassError{nnschart}{nnschart needs LuaLaTeX}{Build with `make pdf <song>'.}
\fi

% ---- options --------------------------------------------------------------
\newcommand\nns@paper{letterpaper}
\DeclareOption{letter}{\renewcommand\nns@paper{letterpaper}}
\DeclareOption{letterpaper}{\renewcommand\nns@paper{letterpaper}}
\DeclareOption{a4}{\renewcommand\nns@paper{a4paper}}
\DeclareOption{a4paper}{\renewcommand\nns@paper{a4paper}}
\newif\ifnns@twocol \nns@twocoltrue
\DeclareOption{onecolumn}{\nns@twocolfalse}
\DeclareOption{twocolumn}{\nns@twocoltrue}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{article}}
\ProcessOptions\relax
\LoadClass[11pt]{article}

\RequirePackage[\nns@paper,margin=0.75in,top=0.5in,bottom=0.5in,
  includeheadfoot,headheight=14pt,headsep=12pt,footskip=24pt]{geometry}
\RequirePackage{fontspec}
\RequirePackage{graphicx}
\RequirePackage{xcolor}
\RequirePackage{multicol}
\RequirePackage{tikz}
\usetikzlibrary{calc,shapes.geometric}

\directlua{nns = require("nns"); nnsmelody = require("nnsmelody")}

\setlength\parindent{0pt}
\setlength\parskip{0pt}
\setlength\lineskip{5pt}% clearance between chord rows

% ---- fonts ----------------------------------------------------------------
\setmainfont{lmsans10-regular.otf}[
  BoldFont=lmsans10-bold.otf,
  ItalicFont=lmsans10-oblique.otf,
  BoldItalicFont=lmsans10-boldoblique.otf]
\newfontfamily\nns@chordfamily{lmsansdemicond10-regular.otf}

% Bravura (SMuFL) is loaded by path from src/fonts; `nns' exports NNS_FONTDIR.
\edef\nns@fontdir{\directlua{tex.sprint(-2, os.getenv("NNS_FONTDIR") or "")}}
\ifx\nns@fontdir\@empty
  \newfontfamily\nns@smuflfont{Bravura.otf}
\else
  \newfontfamily\nns@smuflfont{Bravura.otf}[Path=\nns@fontdir/]
\fi
\newcommand\nns@smufl[1]{{\nns@smuflfont\char"#1\relax}}

\newcommand\nnsChordFont{\nns@chordfamily\fontsize{20}{24}\selectfont}
% jianpu melody digits and the chord labels above them
\newcommand\nnsMelodyFont{\nns@chordfamily\fontsize{13}{16}\selectfont}
\newcommand\nnsMelodyChordFont{\nns@chordfamily\fontsize{16}{18}\selectfont}

% ---- glyphs used in chord labels and marks --------------------------------
\newcommand\nnsFlat{\raisebox{0.18em}{\nns@smufl{E260}}\kern0.03em}
\newcommand\nnsSharp{\raisebox{0.3em}{\nns@smufl{E262}}\kern0.05em}
\newcommand\nnsDoubleFlat{\raisebox{0.18em}{\nns@smufl{E264}}\kern0.03em}
\newcommand\nnsDoubleSharp{\raisebox{0.3em}{\nns@smufl{E263}}\kern0.05em}
\newcommand\nnsMinor{\scalebox{0.8}{m}}
\newcommand\nnsSup[1]{\raisebox{0.42em}{\scalebox{0.58}{#1}}}
\newcommand\nnsSlash[1]{/#1}
\newcommand\nnsPush{\raisebox{0.15em}{\scalebox{0.75}{<}}\kern0.05em}
\newcommand\nnsRest{\raisebox{0.36em}{\scalebox{1.1}{\nns@smufl{E4E5}}}}
\newcommand\nnsTickBox{}
\newcommand\nnsAccentGlyph{\scalebox{1.6}{\nns@smufl{E4AC}}}
\newcommand\nnsNoteGlyph{\raisebox{0.1em}{\scalebox{0.9}{\nns@smufl{ECA5}}}}
\newcommand\nnsDottedNoteGlyph{\raisebox{0.1em}{\scalebox{0.9}{\nns@smufl{ECA5}\,\nns@smufl{ECB7}}}}
% The tempo's beat: a dotted quarter in compound time (6/8, 9/8, 12/8),
% otherwise a quarter.
\newcommand\nns@beatglyph{%
  \ifnum\directlua{
    local n, d = ("\luaescapestring{\nns@time}"):match("^ *([0-9]+) */ *([0-9]+)")
    n = tonumber(n)
    tex.sprint((d == "8" and n and n > 3 and n == 3 * math.floor(n / 3)) and 1 or 0)}=1
    \nnsDottedNoteGlyph\else\nnsNoteGlyph\fi}

% ---- TikZ styles for the grid ---------------------------------------------
\tikzset{
  nnsrow/.style={line cap=butt},
  nnschord/.style={inner sep=1pt,anchor=base west,font=\nnsChordFont},
  nnsglyph/.style={inner sep=1pt,anchor=base west,font=\nnsChordFont},
  nnstick/.style={inner sep=0pt,anchor=base west,minimum width=10pt,minimum height=0pt},
  nnssign/.style={inner sep=0pt,minimum height=0pt,anchor=base west},
  nnstickline/.style={line width=1.6pt,line cap=round},
  nnsunder/.style={line width=1.3pt},
  nnsbracket/.style={line width=1pt},
  nnsbarline/.style={line width=0.6pt,black!55},
  nnsthickbar/.style={line width=2pt,black!80},
  nnsdiamond/.style={line width=1pt},
  nnsstop/.style={regular polygon,regular polygon sides=8,fill,inner sep=0pt,
    minimum size=8pt,anchor=south},
  nnsmute/.style={regular polygon,regular polygon sides=3,draw,line width=0.9pt,
    inner sep=0pt,minimum size=10pt,anchor=south},
  nnsaccent/.style={inner sep=0pt,font=\nnsChordFont,anchor=south},
  nnsbeat/.style={line width=1pt,line cap=round},
  nnsending/.style={line width=0.8pt},
  nnsendinglabel/.style={anchor=north west,inner sep=2pt,font=\small\bfseries},
  nnssection/.style={draw,line width=0.9pt,rounded corners=1.5pt,inner sep=3pt,
    font=\large\bfseries},
  nnsmnote/.style={inner sep=0pt,anchor=base west,font=\nnsMelodyFont},
  nnsmacc/.style={inner sep=0pt,anchor=base east,font=\nnsMelodyFont},
  nnsmdot/.style={},
  nnsmchord/.style={inner sep=0pt,anchor=base west,font=\nnsMelodyChordFont},
  nnsmlabel/.style={inner sep=0pt,anchor=base west,font=\small\bfseries},
  nnsmbeam/.style={line width=0.9pt},
  nnsmdash/.style={line width=1.3pt},
  nnsmtie/.style={line width=0.7pt},
  nnskeychange/.style={fill=black!8,draw=black!60,rounded corners=1.5pt,
    inner sep=3pt,font=\bfseries},
}

% ---- settings -------------------------------------------------------------
\newcommand\nns@title{Untitled}
\newcommand\nns@artist{}
\newcommand\nns@book{}
\newcommand\nns@tempo{}
\newcommand\nns@time{}
\newcommand\nns@feel{}
\newcommand\nns@barsperrow{4}
\newcommand\nns@repeatchords{true}
\pgfkeys{
  /nns/.is family, /nns,
  barsperrow/.store in=\nns@barsperrow,
  repeatchords/.store in=\nns@repeatchords,
  title/.store in=\nns@title,
  artist/.store in=\nns@artist,
  book/.store in=\nns@book,
  tempo/.store in=\nns@tempo,
  time/.store in=\nns@time,
  feel/.store in=\nns@feel,
  key/.code={\directlua{nns.set_key("\luaescapestring{\detokenize{#1}}")}},
  letters/.code={\directlua{nns.config.letters = ("#1" == "true")}},
  letters/.default=true,
}
\newcommand\nnsset[1]{\pgfkeys{/nns,#1}}
\newcommand\songinfo[1]{\nnsset{#1}}

% ---- header and footer ----------------------------------------------------
% Songbook style: small running head (book name left, key/tempo/time/feel
% right) over a rule, a left-aligned bold title, and a footer rule with the
% title left and the artist right.
\newif\ifnns@firstmeta
\newcommand\nnsMetaItem[1]{%
  \ifnns@firstmeta\nns@firstmetafalse\else\enspace·\enspace\fi#1}
\newcommand\nns@meta{%
  \nns@firstmetatrue
  \ifx\nns@keylabel\@empty\else\nnsMetaItem{Key: \nns@keylabel}\fi
  \ifx\nns@tempo\@empty\else\nnsMetaItem{\nns@beatglyph\,=\,\nns@tempo}\fi
  \ifx\nns@time\@empty\else\nnsMetaItem{\nns@time}\fi
  \ifx\nns@feel\@empty\else\nnsMetaItem{\nns@feel}\fi}
\newcommand\nns@ruled[2]{% #1 above the rule (head) or #2 below it (foot)
  \parbox[b]{\textwidth}{\footnotesize#1\ifx\relax#1\relax\else\par\vspace{2pt}\fi
    \hrule height 0.6pt
    \ifx\relax#2\relax\else\vspace{2pt}#2\fi}}
\def\ps@nns{%
  \def\@oddhead{\nns@ruled{\nns@book\hfill\nns@meta}{}}%
  \def\@oddfoot{\nns@ruled{}{\nns@title\hfill\nns@artist}}%
  \let\@evenhead\@oddhead\let\@evenfoot\@oddfoot}
\pagestyle{nns}
\newcommand\nns@header{%
  {\noindent\fontsize{17}{20}\selectfont\bfseries\nns@title\par}\vspace{2pt}}
% The title spans the page; the chart below it is set in two columns
% (class option `onecolumn' turns that off).
\setlength\columnsep{24pt}
\AtBeginDocument{\directlua{nns.store_key_label()}\nns@header
  \ifnns@twocol\begin{multicols}{2}\raggedcolumns\fi}
\AtEndDocument{\ifnns@twocol\end{multicols}\fi}

% ---- song structure -------------------------------------------------------
% \begin{section}{Verse} ... \end{section}
\let\section\relax
\let\endsection\relax
% A section is kept in one piece (a minipage) so it never splits across
% columns or pages.
\newenvironment{section}[1]{%
  \par\addvspace{10pt}%
  \noindent\begin{minipage}{\linewidth}%
  \noindent\tikz[baseline=(l.base)]\node[nnssection](l){#1};\par
  \vspace{2pt}%
  \directlua{nns.begin_section("\luaescapestring{\detokenize{#1}}")}%
}{\par\end{minipage}\par}

% \bars[barsperrow=8]{ | 1 | 4 . 5 | <6m | 4 | }
\NewDocumentCommand\bars{O{}m}{%
  \begingroup\nnsset{#1}%
  \directlua{nns.bars("\luaescapestring{\detokenize{#2}}", "\nns@barsperrow")}%
  \endgroup}

% \melody[barsperrow=2]{ [1] 3 3 4 5 | [5] 5 4 3 2 || }
% A jianpu lead line with its chords; see melody-plan.md and README.md.
\newlength\nns@digitw
\newlength\nns@digith
\newlength\nns@chordw
\NewDocumentCommand\melody{O{}m}{%
  \begingroup\nnsset{#1}%
  \settowidth\nns@digitw{\nnsMelodyFont 0}\settoheight\nns@digith{\nnsMelodyFont 0}%
  \settowidth\nns@chordw{\nnsMelodyChordFont 0}%
  \directlua{nnsmelody.render("\luaescapestring{\detokenize{#2}}", {
    time = "\luaescapestring{\nns@time}", per = "\nns@barsperrow",
    width = "\the\linewidth", repeatchords = "\nns@repeatchords",
    digit_w = "\the\nns@digitw", digit_h = "\the\nns@digith",
    chord_w = "\the\nns@chordw"})}%
  \endgroup}

% Each row of chords is a TikZ picture at its natural width, left-aligned;
% a row too wide for the line is scaled down to fit.
\newsavebox\nns@rowbox
\newcommand\nnsRowBegin{\par\noindent\begin{lrbox}{\nns@rowbox}}
\newcommand\nnsRowEnd{\end{lrbox}%
  \ifdim\wd\nns@rowbox>\linewidth
    \resizebox{\linewidth}{!}{\usebox\nns@rowbox}%
  \else\usebox\nns@rowbox\fi\par}

% \keychange{A}
\newcommand\keychange[1]{%
  \par\directlua{nns.keychange("\luaescapestring{\detokenize{#1}}")}\par}
\newcommand\nnsKeyChange[1]{%
  \addvspace{4pt}\noindent
  \tikz[baseline=(k.base)]\node[nnskeychange](k){\(\rightarrow\)\ Key: #1};%
  \par\nobreak\vspace{2pt}}
