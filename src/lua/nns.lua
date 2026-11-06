-- nns.lua: Nashville Number System bar-string parser and renderer.
--
-- \bars{...} hands its (detokenized) argument to nns.bars(). The string is
-- lexed, parsed into structured bars (chords as degree/accidental/quality/
-- bass), and emitted as one TikZ picture per row of the grid.

local M = {}

M.config = {
  letters = os.getenv("NNS_LETTERS") == "1",
  debug = os.getenv("NNS_DEBUG") == "1", -- echo generated TikZ to the log
}

M.state = {
  section = "(no section)",
  bar = 0,       -- bars emitted so far in the current section
  key = nil,     -- parsed key, see parse_key()
  key_src = nil, -- key as written
}

---------------------------------------------------------------------------
-- Geometry (pt). There are no barlines: every chord is a measure, measures
-- sit side by side at their natural width like words, and chords sharing a
-- measure are packed tighter and underlined.

local BASE        = 10 -- chord baseline
local ROW_H       = 32 -- minimum row height
local UNDER_Y     = 4  -- underline / split-bracket height
local MARK_LO     = 5  -- repeat-sign extent
local MARK_HI     = 28
local END_LO      = 37 -- ending bracket extent (clears diamonds and marks)
local END_HI      = 49
local MEASURE_GAP = 17 -- between measures
local SPLIT_GAP   = 6  -- between chords (or ticks) within one measure
local SIGN_GAP    = 5  -- around repeat signs
local DIAMOND_PAD = 9  -- extra room on each side of a diamond

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local CT_ATLETTER = luatexbase and luatexbase.registernumber("catcodetable@atletter")

local function out(s)
  if M.config.debug then texio.write_nl("log", "nns> " .. s) end
  if CT_ATLETTER then tex.print(CT_ATLETTER, s) else tex.print(s) end
end

local function num(x)
  return (string.format("%.4f", x):gsub("0+$", ""):gsub("%.$", ""))
end

local function report(barno, fmt, ...)
  local msg = string.format(fmt, ...)
  tex.error(string.format("nns: %s in bar %d of section '%s'", msg, barno, M.state.section), {
    "The \\bars string could not be understood. See README.md for the",
    "notation (chords like 1 4 5 6m b7 5/7, marks like < * ! ^ r /).",
  })
end

local ACC_OFFSET = { [""] = 0, b = -1, ["#"] = 1 }

local ACC_TEX = {
  [-2] = "\\nnsDoubleFlat{}",
  [-1] = "\\nnsFlat{}",
  [0]  = "",
  [1]  = "\\nnsSharp{}",
  [2]  = "\\nnsDoubleSharp{}",
}

---------------------------------------------------------------------------
-- Keys and letter names (for --letters, and for key labels)
---------------------------------------------------------------------------

local LETTERS = { "C", "D", "E", "F", "G", "A", "B" }
local NATURAL = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local MAJOR   = { 0, 2, 4, 5, 7, 9, 11 }
local MINOR   = { 0, 2, 3, 5, 7, 8, 10 }

local function parse_key(s)
  s = s:gsub("##", "#")
  local l, a, m = s:match("^%s*([A-Ga-g])([b#]?)(m?)%s*$")
  if not l then return nil end
  l = l:upper()
  local idx
  for i, v in ipairs(LETTERS) do if v == l then idx = i end end
  return {
    letter = idx,
    semi = (NATURAL[l] + ACC_OFFSET[a]) % 12,
    minor = m == "m",
    acc = ACC_OFFSET[a],
  }
end

local function key_label(k)
  return LETTERS[k.letter] .. ACC_TEX[k.acc] .. (k.minor and "m" or "")
end

-- Spell scale degree `deg` (1-7) altered by `acc` semitones in key `k`.
local function spell(k, deg, acc)
  local li = (k.letter + deg - 2) % 7 + 1
  local letter = LETTERS[li]
  local scale = k.minor and MINOR or MAJOR
  local semi = (k.semi + scale[deg] + acc) % 12
  local diff = (semi - NATURAL[letter]) % 12
  if diff > 6 then diff = diff - 12 end
  if diff < -2 or diff > 2 then return letter .. "?" end
  return letter .. ACC_TEX[diff]
end

function M.set_key(s)
  s = s:gsub("##", "#")
  local k = parse_key(s)
  if not k then
    tex.error(string.format("nns: cannot understand key '%s' (expected e.g. G, Bb, F#, Am)", s))
    return
  end
  M.state.key, M.state.key_src = k, s
end

-- Defines \nns@keylabel (globally) as the current key, typeset, or empty.
-- Called once at \begin{document} so the running head keeps the song's key.
function M.store_key_label()
  token.set_macro("nns@keylabel", M.state.key and key_label(M.state.key) or "", "global")
end

function M.keychange(s)
  M.set_key(s)
  if M.state.key then out("\\nnsKeyChange{" .. key_label(M.state.key) .. "}") end
end

---------------------------------------------------------------------------
-- Chords
---------------------------------------------------------------------------

-- Quality pieces, tried in order at each position of the quality string.
-- Each maps the matched text to TeX for the superscript.
local QUALITY_PIECES = {
  { "^maj",  function() return "maj" end },
  { "^Δ",    function() return "\\ensuremath{\\Delta}" end },
  { "^sus",  function() return "sus" end },
  { "^add",  function() return "add" end },
  { "^dim",  function() return "°" end },
  { "^°",    function() return "°" end },
  { "^ø",    function() return "ø" end },
  { "^aug",  function() return "+" end },
  { "^%+",   function() return "+" end },
  { "^alt",  function() return "alt" end },
  { "^b",    function() return "\\nnsFlat{}" end },
  { "^#",    function() return "\\nnsSharp{}" end },
  { "^%d+",  function(s) return s end },
  { "^[()]", function(s) return s end },
}

local function parse_quality(q)
  local minor = false
  if q:match("^m") and not q:match("^maj") then
    minor, q = true, q:sub(2)
  elseif q:match("^%-") then
    minor, q = true, q:sub(2)
  end
  local sup = {}
  while #q > 0 do
    local hit = false
    for _, p in ipairs(QUALITY_PIECES) do
      local s = q:match(p[1])
      if s then
        sup[#sup + 1] = p[2](s)
        q = q:sub(#s + 1)
        hit = true
        break
      end
    end
    if not hit then return nil end
  end
  return minor, table.concat(sup)
end

local function parse_degree(s)
  local a, d = s:match("^([b#]?)([1-7])$")
  if not d then return nil end
  return { acc = ACC_OFFSET[a], degree = tonumber(d) }
end

-- Returns a chord table, or nil if `w` is not a chord.
local function parse_chord(w, suffixes)
  local push = false
  if w:sub(1, 1) == "<" then push, w = true, w:sub(2) end

  local mods, beats = {}, 0
  while #w > 1 and suffixes[w:sub(-1)] do
    local m = suffixes[w:sub(-1)]
    if m.name == "beats" then
      -- one mod draws all the ticks; count the apostrophes
      if beats == 0 then table.insert(mods, 1, m) end
      beats = beats + 1
    else
      table.insert(mods, 1, m)
    end
    w = w:sub(1, -2)
  end

  local main, bass = w:match("^([^/]+)/(.+)$")
  main = main or w
  local a, d, q = main:match("^([b#]?)([1-7])(.*)$")
  if not d then return nil end
  local minor, sup = parse_quality(q)
  if minor == nil then return nil end
  local b
  if bass then
    b = parse_degree(bass)
    if not b then return nil end
  end
  return {
    kind = "chord", push = push, acc = ACC_OFFSET[a], degree = tonumber(d),
    minor = minor, sup = sup, bass = b, mods = mods, beats = beats,
  }
end

local function degree_tex(acc, degree)
  if M.config.letters and M.state.key then
    return spell(M.state.key, degree, acc)
  end
  return ACC_TEX[acc] .. degree
end

local function chord_tex(c)
  local s = degree_tex(c.acc, c.degree)
  if c.minor then s = s .. "\\nnsMinor{}" end
  if c.sup ~= "" then s = s .. "\\nnsSup{" .. c.sup .. "}" end
  if c.bass then s = s .. "\\nnsSlash{" .. degree_tex(c.bass.acc, c.bass.degree) .. "}" end
  if c.push then s = "\\nnsPush{}" .. s end
  return s
end

---------------------------------------------------------------------------
-- Marks: token pattern -> drawing function.
--
--   kind "item"   takes a beat slot in the bar. draw(id, x, y) -> TikZ
--   kind "mod"    decorates the preceding chord. draw(id, k) -> TikZ,
--                 where k counts marks already stacked above the chord.
--                 `suffix` lets the mark be glued onto a chord ("1*").
--   kind "prefix" applies to the next chord.
--
-- Adding a mark = one entry here + (usually) one TikZ style in nnschart.cls.
---------------------------------------------------------------------------

local function above(id, k, style, body)
  return string.format("\\node[%s] at ([yshift=%dpt]%s.north) {%s};", style, 2 + 10 * k, id, body or "")
end

M.marks = {
  { name = "rest", pattern = "^r$", kind = "item",
    draw = function(id, at)
      return string.format("\\node[nnsglyph] (%s) at %s {\\nnsRest};", id, at)
    end },

  { name = "tick", pattern = "^/$", kind = "item",
    draw = function(id, at)
      return string.format("\\node[nnstick] (%s) at %s {\\nnsTickBox};", id, at)
        .. string.format("\\draw[nnstickline] ([shift={(1.5pt,1pt)}]%s.base west) -- ++(7pt,14pt);", id)
    end },

  { name = "diamond", pattern = "^\\diamond$", suffix = "*", kind = "mod", stacks = false,
    draw = function(id)
      local c = id .. ".center"
      return "\\draw[nnsdiamond] let \\p1=($(" .. id .. ".north east)-(" .. c .. ")$) in "
        .. "($(" .. c .. ")+({-(\\x1+0.8*\\y1+2pt)},0)$) -- "
        .. "($(" .. c .. ")+(0,{\\y1+\\x1/0.8+2pt})$) -- "
        .. "($(" .. c .. ")+({\\x1+0.8*\\y1+2pt},0)$) -- "
        .. "($(" .. c .. ")+(0,{-(\\y1+\\x1/0.8+2pt)})$) -- cycle;"
    end },

  { name = "stop", pattern = "^!$", suffix = "!", kind = "mod", stacks = true,
    draw = function(id, k) return above(id, k, "nnsstop") end },

  { name = "accent", pattern = "^%^$", suffix = "^", kind = "mod", stacks = true,
    draw = function(id, k) return above(id, k, "nnsaccent", "\\nnsAccentGlyph") end },

  { name = "mute", pattern = "^\\mute$", kind = "mod", stacks = true,
    draw = function(id, k) return above(id, k, "nnsmute") end },

  -- Beat count over a chord in a split bar: 4''' . 6m' (6m lands on beat 4).
  { name = "beats", pattern = "^'+$", suffix = "'", kind = "mod", stacks = true,
    draw = function(id, k, chord)
      local out = {}
      for i = 1, chord.beats do
        out[#out + 1] = string.format(
          "\\draw[nnsbeat] ([xshift=%.1fpt,yshift=%dpt]%s.north) -- ++(1.2pt,5pt);",
          (i - (chord.beats + 1) / 2) * 3.5 - 0.6, 3 + 10 * k, id)
      end
      return table.concat(out)
    end },

  { name = "push", pattern = "^<$", kind = "prefix",
    apply = function(chord) chord.push = true end },
}

local SUFFIXES = {}
for _, m in ipairs(M.marks) do
  if m.suffix then SUFFIXES[m.suffix] = m end
end

local function find_mark(w)
  for _, m in ipairs(M.marks) do
    if w:match(m.pattern) then return m end
  end
end

---------------------------------------------------------------------------
-- Lexer
---------------------------------------------------------------------------

local function lex(s)
  local toks, i, n = {}, 1, #s
  local function push(t) toks[#toks + 1] = t end
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif s:sub(i, i + 2) == ":|:" then push { t = "bar", style = "repeat-both" }; i = i + 3
    elseif s:sub(i, i + 1) == "|:" then push { t = "bar", style = "repeat-start" }; i = i + 2
    elseif s:sub(i, i + 1) == ":|" then push { t = "bar", style = "repeat-end" }; i = i + 2
    elseif s:sub(i, i + 1) == "||" then push { t = "bar", style = "double" }; i = i + 2
    elseif c == "|" then push { t = "bar", style = "single" }; i = i + 1
    elseif s:match("^%[%d+%.", i) then
      local d = s:match("^%[(%d+)%.", i)
      push { t = "ending", n = tonumber(d) }; i = i + #d + 2
    elseif c == "[" then push { t = "open" }; i = i + 1
    elseif c == "]" then push { t = "close" }; i = i + 1
    elseif c == "." then push { t = "dot" }; i = i + 1
    else
      local w
      if c == "\\" then w = s:match("^\\%a+", i) or "\\"
      else w = s:match("^[^%s|%[%]\\%.]+", i) end
      push { t = "word", v = w }; i = i + #w
    end
  end
  return toks
end

---------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------

local function parse(src)
  local bars, cur, lastsep, pending_push = {}, nil, "single", false
  local seps_in_a_row = 0

  local function barno() return M.state.bar + #bars + 1 end
  local function open_bar()
    if not cur then cur = { items = {}, groups = {}, left = lastsep } end
    return cur
  end

  for _, tok in ipairs(lex(src)) do
    if tok.t == "bar" then
      if cur and #cur.items > 0 then
        if cur.group_open then report(barno(), "unclosed '['"); cur.group_open = nil end
        cur.right = tok.style
        bars[#bars + 1] = cur
        cur = nil
      elseif cur then
        report(barno(), "bar has an ending mark but no chords")
        cur = nil
      elseif #bars > 0 and seps_in_a_row > 0 then
        report(barno(), "empty bar")
      end
      lastsep = tok.style
      seps_in_a_row = seps_in_a_row + 1
    else
      seps_in_a_row = 0
      local b = open_bar()
      if tok.t == "ending" then
        if #b.items > 0 then report(barno(), "ending '[%d.' must come right after a barline", tok.n)
        else b.ending = tok.n end
      elseif tok.t == "open" then
        if b.group_open then report(barno(), "nested '['")
        else b.group_open = #b.items + 1 end
      elseif tok.t == "close" then
        if not b.group_open then report(barno(), "']' without '['")
        elseif #b.items < b.group_open then report(barno(), "empty '[ ]'"); b.group_open = nil
        else
          b.groups[#b.groups + 1] = { from = b.group_open, to = #b.items }
          b.group_open = nil
        end
      elseif tok.t == "dot" then
        b.dotted = true
      else
        local w = tok.v
        local m = find_mark(w)
        if m and m.kind == "item" then
          b.items[#b.items + 1] = { kind = m.name, mark = m }
        elseif m and m.kind == "mod" then
          local prev = b.items[#b.items]
          if prev and prev.kind == "chord" and m.name == "beats" then
            if prev.beats == 0 then prev.mods[#prev.mods + 1] = m end
            prev.beats = prev.beats + #w
          elseif prev and prev.kind == "chord" then
            prev.mods[#prev.mods + 1] = m
          else
            report(barno(), "'%s' must follow a chord", w)
          end
        elseif m and m.kind == "prefix" then
          pending_push = m
        else
          local c = parse_chord(w, SUFFIXES)
          if c then
            if pending_push then pending_push.apply(c); pending_push = false end
            b.items[#b.items + 1] = c
          else
            report(barno(), "unknown token '%s'", w)
          end
        end
      end
    end
  end

  if cur then
    if #cur.items > 0 then
      if cur.group_open then report(barno(), "unclosed '['") end
      cur.right = "single"
      bars[#bars + 1] = cur
    else
      report(barno(), "bar has an ending mark but no chords")
    end
  end

  -- Ending spans: from a bar marked [n. up to the first bar that closes with
  -- a repeat or double bar, the bar before the next ending, or the last bar.
  local spans = {}
  for i, b in ipairs(bars) do
    if b.ending then
      local j = i
      while j < #bars do
        local r = bars[j].right
        if r == "repeat-end" or r == "repeat-both" or r == "double" or bars[j + 1].ending then break end
        j = j + 1
      end
      local r = bars[j].right
      spans[#spans + 1] = { n = b.ending, from = i, to = j,
                            closed = (r == "repeat-end" or r == "repeat-both") }
    end
  end

  return bars, spans
end

---------------------------------------------------------------------------
-- Renderer
---------------------------------------------------------------------------

local function pt(v) return num(v) .. "pt" end

local function emit_row(row, rowstart, spans)
  local k = #row
  local first, last = rowstart, rowstart + k - 1

  local has_ending = false
  for _, sp in ipairs(spans) do
    if sp.to >= first and sp.from <= last then has_ending = true end
  end

  out("\\nnsRowBegin\\begin{tikzpicture}[nnsrow]")
  out(string.format("\\path (0,0) rectangle (0,%s);", pt(ROW_H + (has_ending and END_HI - ROW_H + 2 or 0))))
  out(string.format("\\coordinate (nnsU) at (0,%s);", pt(UNDER_Y)))
  out(string.format("\\coordinate (nnsEL) at (0,%s);", pt(END_LO)))
  out(string.format("\\coordinate (nnsEH) at (0,%s);", pt(END_HI)))

  -- Everything is placed left to right: each element is anchored at its
  -- base west, `gap` points after the previous element's base east.
  local prev, nsigns = nil, 0
  local function at(gap)
    if prev then return string.format("([xshift=%s]%s.base east)", pt(gap), prev) end
    return string.format("(%s,%s)", pt(0), pt(BASE))
  end

  -- Repeat and double-bar signs: an empty node of fixed width, drawn into.
  local function sign(kind, gap)
    nsigns = nsigns + 1
    local id = "nnsS" .. nsigns
    local w = kind == "double" and 4 or 9
    out(string.format("\\node[nnssign,minimum width=%s] (%s) at %s {};", pt(w), id, at(gap)))
    local function line(dx, style)
      return string.format("\\draw[%s] ([shift={(%s,%s)}]%s.base west) -- ++(0,%s);",
        style, pt(dx), pt(MARK_LO - BASE), id, pt(MARK_HI - MARK_LO))
    end
    local function dots(dx)
      local mid = (MARK_LO + MARK_HI) / 2 - BASE
      return string.format("\\fill ([shift={(%s,%s)}]%s.base west) circle[radius=1.3pt];", pt(dx), pt(mid - 4), id)
        .. string.format("\\fill ([shift={(%s,%s)}]%s.base west) circle[radius=1.3pt];", pt(dx), pt(mid + 4), id)
    end
    if kind == "start" then out(line(1, "nnsthickbar") .. line(4.5, "nnsbarline") .. dots(7.7))
    elseif kind == "end" then out(dots(1.3) .. line(4.5, "nnsbarline") .. line(8, "nnsthickbar"))
    else out(line(0.5, "nnsbarline") .. line(3.5, "nnsbarline")) end
    prev = id
    return id
  end

  local measures = {}
  local gap = 0
  for j, b in ipairs(row) do
    local m = {}
    measures[j] = m
    local opens = (j == 1) and b.left or row[j - 1].right
    if opens == "repeat-start" or opens == "repeat-both" then
      m.first = sign("start", gap)
      gap = SIGN_GAP
    end

    local chords, n, pad = 0, #b.items, 0
    for i, it in ipairs(b.items) do
      local id = string.format("nns%d-%d", j, i)
      it.id = id
      pad = 0
      if it.kind == "chord" then
        for _, md in ipairs(it.mods) do if md.name == "diamond" then pad = DIAMOND_PAD end end
      end
      local here = at(gap + pad)
      if it.kind == "chord" then
        chords = chords + 1
        out(string.format("\\node[nnschord] (%s) at %s {%s};", id, here, chord_tex(it)))
        local stacked = 0
        for _, md in ipairs(it.mods) do
          out(md.draw(id, stacked, it))
          if md.stacks then stacked = stacked + 1 end
        end
      else
        out(it.mark.draw(id, here))
      end
      prev = id
      if not m.first then m.first, m.firstpad = id, pad end
      gap = SPLIT_GAP + pad
    end
    m.last = prev

    -- split measures: brackets for [ ] groups, otherwise underline >1 chord
    if #b.groups > 0 then
      for _, g in ipairs(b.groups) do
        out(string.format("\\draw[nnsbracket] (%s.west |- nnsU) ++(0,4pt) |- (%s.east |- nnsU) -- ++(0,4pt);",
          b.items[g.from].id, b.items[g.to].id))
      end
    elseif chords > 1 then
      out(string.format("\\draw[nnsunder] (%s.west |- nnsU) -- (%s.east |- nnsU);",
        b.items[1].id, b.items[n].id))
    end

    gap = gap - SPLIT_GAP + MEASURE_GAP
    if b.right == "repeat-end" or b.right == "repeat-both" then
      m.last = sign("end", SIGN_GAP + pad)
      gap = MEASURE_GAP
    elseif b.right == "double" then
      m.last = sign("double", SIGN_GAP + 1 + pad)
      gap = MEASURE_GAP
    end
  end

  -- endings: bracket over the measures they cover
  for _, sp in ipairs(spans) do
    if sp.to >= first and sp.from <= last then
      local starts, ends = sp.from >= first, sp.to <= last
      local fm = measures[sp.from - first + 1]
      local a = starts and string.format("([xshift=%s]%s.west |- nnsEL)", pt(-3 - (fm.firstpad or 0)), fm.first)
                       or string.format("(0,%s)", pt(END_LO))
      local zid = measures[math.min(sp.to, last) - first + 1].last
      local p = a .. string.format(" |- ([xshift=3pt]%s.east |- nnsEH)", zid)
      if ends and sp.closed then p = p .. " -- ++(0," .. pt(END_LO - END_HI) .. ")" end
      out("\\draw[nnsending] " .. p .. ";")
      if starts then
        out(string.format("\\node[nnsendinglabel] at ([xshift=%s]%s.west |- nnsEH) {%d.};",
          pt(-1 - (fm.firstpad or 0)), fm.first, sp.n))
      end
    end
  end

  out("\\end{tikzpicture}\\nnsRowEnd")
end

function M.begin_section(name)
  M.state.section = name
  M.state.bar = 0
end

function M.bars(src, per)
  src = src:gsub("##", "#")
  per = tonumber(per) or 4
  if per < 1 then per = 4 end
  local bars, spans = parse(src)
  for r = 1, #bars, per do
    local row = {}
    for j = r, math.min(r + per - 1, #bars) do row[#row + 1] = bars[j] end
    emit_row(row, r, spans)
  end
  M.state.bar = M.state.bar + #bars
end

-- exported for tests / tooling
M._parse = parse
M._parse_chord = function(w) return parse_chord(w, SUFFIXES) end
M._spell = spell
M._parse_key = parse_key

return M
