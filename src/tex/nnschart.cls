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
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{article}}
\ProcessOptions\relax
\LoadClass[11pt]{article}

\RequirePackage[\nns@paper,margin=0.75in]{geometry}
\RequirePackage{fontspec}
\RequirePackage{graphicx}
\RequirePackage{xcolor}
\RequirePackage{tikz}
\usetikzlibrary{calc,shapes.geometric}

\directlua{nns = require("nns")}

\pagestyle{empty}
\setlength\parindent{0pt}
\setlength\parskip{0pt}

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

% ---- glyphs used in chord labels and marks --------------------------------
\newcommand\nnsFlat{\raisebox{0.18em}{\nns@smufl{E260}}\kern0.03em}
\newcommand\nnsSharp{\raisebox{0.3em}{\nns@smufl{E262}}\kern0.05em}
\newcommand\nnsDoubleFlat{\raisebox{0.18em}{\nns@smufl{E264}}\kern0.03em}
\newcommand\nnsDoubleSharp{\raisebox{0.3em}{\nns@smufl{E263}}\kern0.05em}
\newcommand\nnsMinor{\scalebox{0.8}{m}}
\newcommand\nnsSup[1]{\raisebox{0.42em}{\scalebox{0.58}{#1}}}
\newcommand\nnsSlash[1]{/#1}
\newcommand\nnsPush{\raisebox{0.15em}{\scalebox{0.75}{<}}\kern0.05em}
\newcommand\nnsRest{\scalebox{1.1}{\nns@smufl{E4E5}}}
\newcommand\nnsAccentGlyph{\scalebox{1.6}{\nns@smufl{E4AC}}}
\newcommand\nnsNoteGlyph{\raisebox{0.1em}{\scalebox{0.9}{\nns@smufl{ECA5}}}}

% ---- TikZ styles for the grid ---------------------------------------------
\tikzset{
  nnsrow/.style={line cap=butt},
  nnschord/.style={inner sep=1pt,font=\nnsChordFont},
  nnsglyph/.style={inner sep=1pt,font=\nnsChordFont},
  nnstick/.style={inner sep=0pt,minimum width=8pt,minimum height=14pt},
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
  nnsending/.style={line width=0.8pt},
  nnsendinglabel/.style={anchor=north west,inner sep=2pt,font=\small\bfseries},
  nnssection/.style={draw,line width=0.9pt,rounded corners=1.5pt,inner sep=3pt,
    font=\large\bfseries},
  nnskeychange/.style={fill=black!8,draw=black!60,rounded corners=1.5pt,
    inner sep=3pt,font=\bfseries},
}

% ---- settings -------------------------------------------------------------
\newcommand\nns@title{Untitled}
\newcommand\nns@artist{}
\newcommand\nns@tempo{}
\newcommand\nns@time{}
\newcommand\nns@feel{}
\newcommand\nns@barsperrow{4}
\pgfkeys{
  /nns/.is family, /nns,
  barsperrow/.store in=\nns@barsperrow,
  title/.store in=\nns@title,
  artist/.store in=\nns@artist,
  tempo/.store in=\nns@tempo,
  time/.store in=\nns@time,
  feel/.store in=\nns@feel,
  key/.code={\directlua{nns.set_key("\luaescapestring{\detokenize{#1}}")}},
  letters/.code={\directlua{nns.config.letters = ("#1" == "true")}},
  letters/.default=true,
}
\newcommand\nnsset[1]{\pgfkeys{/nns,#1}}
\newcommand\songinfo[1]{\nnsset{#1}}

% ---- header ---------------------------------------------------------------
\newif\ifnns@firstmeta
\newcommand\nnsMetaItem[1]{%
  \ifnns@firstmeta\nns@firstmetafalse\else\quad·\quad\fi#1}
\newcommand\nns@header{%
  \begin{center}
    {\fontsize{24}{28}\selectfont\bfseries\nns@title\par}
    \ifx\nns@artist\@empty\else\vspace{3pt}{\large\nns@artist\par}\fi
    \vspace{6pt}
    {\large\nns@firstmetatrue
     \directlua{nns.print_key_label("Key: ")}%
     \ifx\nns@tempo\@empty\else\nnsMetaItem{\nnsNoteGlyph\,=\,\nns@tempo}\fi
     \ifx\nns@time\@empty\else\nnsMetaItem{\nns@time}\fi
     \ifx\nns@feel\@empty\else\nnsMetaItem{\nns@feel}\fi
     \par}
  \end{center}
  \vspace{-6pt}\noindent\rule{\linewidth}{0.6pt}\par\vspace{6pt}}
\AtBeginDocument{\nns@header}

% ---- song structure -------------------------------------------------------
% \begin{section}{Verse} ... \end{section}
\let\section\relax
\let\endsection\relax
\newenvironment{section}[1]{%
  \par\addvspace{10pt}%
  \noindent\tikz[baseline=(l.base)]\node[nnssection](l){#1};\par
  \nobreak\vspace{2pt}\nobreak
  \directlua{nns.begin_section("\luaescapestring{\detokenize{#1}}")}%
}{\par}

% \bars[barsperrow=8]{ | 1 | 4 . 5 | <6m | 4 | }
\NewDocumentCommand\bars{O{}m}{%
  \begingroup\nnsset{#1}%
  \directlua{nns.bars("\luaescapestring{\detokenize{#2}}", "\nns@barsperrow")}%
  \endgroup}

% \keychange{A}
\newcommand\keychange[1]{%
  \par\directlua{nns.keychange("\luaescapestring{\detokenize{#1}}")}\par}
\newcommand\nnsKeyChange[1]{%
  \addvspace{4pt}\noindent
  \tikz[baseline=(k.base)]\node[nnskeychange](k){\(\rightarrow\)\ Key: #1};%
  \par\nobreak\vspace{2pt}}
