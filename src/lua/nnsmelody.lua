-- nnsmelody.lua: jianpu (numbered) melody lines for \melody{...}.
--
-- Pipeline: lex -> parse (with validation) -> layout -> emit. Everything up
-- to and including layout is plain Lua with no TeX calls, so
-- tests/melody_test.lua can drive it with texlua. See melody-plan.md.
--
-- Durations are counted in units of the time signature's denominator: a
-- bare note is a quarter in 4/4 and an eighth in 6/8.

local nns = require("nns")

local M = {}

---------------------------------------------------------------------------
-- Geometry (pt). Every unit of the bar gets the same width U, so events
-- that start on the same beat line up across voices and with their chords.

-- Digit metrics are measured in the melody font by \melody (see layout).
local DIGIT_W    = 8    -- advance of a melody digit
local DIGIT_H    = 11.6 -- digit height above the baseline
local LEAD       = 11   -- from a bar line to the bar's first note
local REPEAT_PAD = 4    -- extra lead-in after a start-repeat sign
local U_MIN      = { [0] = 18, [1] = 24, [2] = 40 } -- by finest underline level
local U_MAX      = 30
local LABEL_W    = 16   -- voice-label gutter
local STACK_GAP  = 5.4  -- clear space between stacked digits
local DOT_R      = 1.25
local DOT_GAP    = 2.6  -- digit edge (or lowest underline) to first octave dot
local DOT_STEP   = 4
local LINE_Y0    = 2.2  -- first underline below the baseline
local LINE_STEP  = 2.8
local DASH_W     = 7
local VOICE_GAP  = 13
local CHORD_GAP  = 6    -- top of the top voice to the chord baseline
local CHORD_H    = 13
local CHORD_PAD  = 4    -- least space after a chord label before the next
local TIE_H      = 6
local END_RISE   = 9    -- ending bracket hook height

---------------------------------------------------------------------------
-- Lexer
---------------------------------------------------------------------------

local function lex(src)
  local toks, i, n = {}, 1, #src
  local function push(t, len) t.col = i; toks[#toks + 1] = t; i = i + len end
  while i <= n do
    local c = src:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif src:sub(i, i + 2) == ":|:" then push({ t = "bar", style = "repeat-both" }, 3)
    elseif src:sub(i, i + 1) == "|:" then push({ t = "bar", style = "repeat-start" }, 2)
    elseif src:sub(i, i + 1) == ":|" then push({ t = "bar", style = "repeat-end" }, 2)
    elseif src:sub(i, i + 1) == "||" then push({ t = "bar", style = "double" }, 2)
    elseif c == "|" then push({ t = "bar", style = "single" }, 1)
    elseif src:match("^%[%d+%.", i) then
      local d = src:match("^%[(%d+)%.", i)
      push({ t = "ending", n = tonumber(d) }, #d + 2)
    elseif c == "[" then
      local j = src:find("]", i, true)
      if not j then push({ t = "bad", v = src:sub(i) }, n - i + 1)
      else push({ t = "chord", v = src:sub(i + 1, j - 1) }, j - i + 1) end
    elseif c == "(" then
      local j = src:find(")", i, true)
      if not j then push({ t = "bad", v = src:sub(i) }, n - i + 1)
      else
        local dur = src:match("^[/%.]*", j + 1)
        push({ t = "stack", v = src:sub(i + 1, j - 1), dur = dur }, j - i + 1 + #dur)
      end
    elseif c == "-" then push({ t = "hold" }, 1)
    elseif c == "~" then push({ t = "tie" }, 1)
    else
      local name = src:match("^(%a[%w_]*):", i)
      if name and src:sub(i + #name + 1, i + #name + 1) ~= "|" then
        push({ t = "voice", v = name }, #name + 1)
      else
        local w = src:match("^[b#]?%d[',]*[/%.]*", i) or src:match("^%S+", i)
        push({ t = w:match("^[b#]?%d") and "note" or "bad", v = w }, #w)
      end
    end
  end
  return toks
end

---------------------------------------------------------------------------
-- Parser and validator
---------------------------------------------------------------------------

local function parse_time(s)
  local b, u = (s or ""):match("^%s*(%d+)%s*/%s*(%d+)")
  return { beats = tonumber(b) or 4, unit = tonumber(u) or 4, label = b and (b .. "/" .. u) or "4/4" }
end
M.parse_time = parse_time

-- "b3'" -> pitch, or nil and an error message
local function parse_pitch(w)
  local acc, d, oct = w:match("^([b#]?)(%d)([',]*)$")
  if not d then return nil, string.format("can't read note '%s'", w) end
  d = tonumber(d)
  if d < 1 or d > 7 then return nil, string.format("scale degrees are 1-7, not '%s'", w) end
  local o = 0
  for ch in oct:gmatch(".") do o = o + (ch == "'" and 1 or -1) end
  if math.abs(o) > 2 then return nil, string.format("'%s' is more than two octaves from the tonic", w) end
  return { acc = acc, deg = d, oct = o }
end

-- "/", "//", ".", "/.", "//." -> units, underline count, dotted
local function parse_dur(s, w)
  local sl, dot, rest = s:match("^(/*)(%.?)(.*)$")
  if rest ~= "" or #sl > 2 then return nil, string.format("can't read the length of '%s'", w) end
  local units = 0.5 ^ #sl
  if dot == "." then units = units * 1.5 end
  return units, #sl, dot == "."
end

local function pitch_key(p) return p.oct * 7 + p.deg + (p.acc == "b" and -0.5 or p.acc == "#" and 0.5 or 0) end

local function same_pitches(a, b)
  if #a.pitches ~= #b.pitches then return false end
  for i, p in ipairs(a.pitches) do
    local q = b.pitches[i]
    if p.deg ~= q.deg or p.acc ~= q.acc or p.oct ~= q.oct then return false end
  end
  return true
end

local function fmt(x) return (string.format("%.4f", x):gsub("0+$", ""):gsub("%.$", "")) end

-- Returns tree, errors, warnings. Each error/warning is { msg, bar, voice }.
function M.parse(src, time)
  time = time or parse_time("4/4")
  local errs, warns = {}, {}
  local voices, byname = {}, {}
  local v

  local function note_err(list, fmtstr, ...)
    list[#list + 1] = {
      msg = string.format(fmtstr, ...),
      voice = v and v.name ~= "" and v.name or nil,
      bar = v and (#v.bars + 1) or 1,
    }
  end
  local function err(...) note_err(errs, ...) end
  local function warn(...) note_err(warns, ...) end

  local function use_voice(name)
    if not byname[name] then
      byname[name] = { name = name, bars = {}, lastsep = "single", seps = 0 }
      voices[#voices + 1] = byname[name]
    end
    v = byname[name]
  end

  local function open_bar()
    if not v then use_voice("") end
    if not v.cur then v.cur = { ev = {}, chords = {}, pos = 0, left = v.lastsep } end
    v.seps = 0
    return v.cur
  end

  local function close_bar(style)
    if not v then use_voice("") end
    local b = v.cur
    if b and #b.ev > 0 then
      if v.pending then
        err("chord [%s] has no note, rest or hold after it in the bar", v.pending.src)
        v.pending = nil
      end
      b.right = style
      v.bars[#v.bars + 1] = b
    elseif b then
      err("bar has no notes")
    elseif #v.bars > 0 and v.seps > 0 then
      err("empty bar")
    end
    v.cur = nil
    v.lastsep = style
    v.seps = v.seps + 1
  end

  local function add_event(e)
    local b = open_bar()
    e.start = b.pos
    b.pos = b.pos + e.units
    if v.pending then
      b.chords[#b.chords + 1] = { beat = e.start, chord = v.pending.chord, src = v.pending.src }
      v.pending = nil
    end
    if v.tie_open then
      local a = v.tie_open
      if e.kind == "rest" then
        err("tie into a rest")
      elseif not same_pitches(a, e) then
        warn("tie joins different pitches")
      end
      a.tie_to, e.tie_from = e, a
      v.tie_open = nil
    end
    b.ev[#b.ev + 1] = e
    v.last = e
  end

  for _, tok in ipairs(lex(src)) do
    if tok.t == "voice" then
      if v and v.cur and #v.cur.ev > 0 then close_bar("single") end
      use_voice(tok.v)
    elseif tok.t == "bar" then
      close_bar(tok.style)
    elseif tok.t == "ending" then
      local b = open_bar()
      if #b.ev > 0 then err("ending '[%d.' must come right after a bar line", tok.n)
      else b.ending = tok.n end
    elseif tok.t == "chord" then
      open_bar()
      if v.pending then err("chord [%s] follows chord [%s] with no note between", tok.v, v.pending.src) end
      local c = nns.parse_chord_symbol(tok.v)
      if not c then
        err("can't read chord [%s]", tok.v)
      elseif c.push or #c.mods > 0 then
        err("chord [%s]: pushes and marks aren't used in melodies; attach the chord to the note where it lands", tok.v)
      else
        v.pending = { chord = c, src = tok.v }
      end
    elseif tok.t == "note" then
      local head, dur = tok.v:match("^([b#]?%d[',]*)(.*)$")
      local units, lines, dotted = parse_dur(dur, tok.v)
      if not units then err("%s", lines) else
        if head:match("^0") then
          if head ~= "0" then err("a rest is just 0, not '%s'", tok.v)
          else add_event({ kind = "rest", units = units, lines = lines, dotted = dotted, holds = 0 }) end
        else
          local p, msg = parse_pitch(head)
          if not p then err("%s", msg)
          else add_event({ kind = "note", pitches = { p }, units = units, lines = lines, dotted = dotted, holds = 0 }) end
        end
      end
    elseif tok.t == "stack" then
      local units, lines, dotted = parse_dur(tok.dur, "(" .. tok.v .. ")" .. tok.dur)
      local ps, seen, ok = {}, {}, true
      for w in tok.v:gmatch("%S+") do
        local p, msg = parse_pitch(w)
        if not p then err("in stack (%s): %s", tok.v, msg); ok = false
        else
          local k = pitch_key(p)
          if seen[k] then warn("duplicate pitch %s in stack (%s)", w, tok.v) end
          seen[k] = true
          ps[#ps + 1] = p
        end
      end
      if #ps == 0 and ok then err("empty stack ()"); ok = false end
      if not units then err("%s", lines); ok = false end
      if ok then
        table.sort(ps, function(a, b) return pitch_key(a) < pitch_key(b) end)
        add_event({ kind = "stack", pitches = ps, units = units, lines = lines, dotted = dotted, holds = 0 })
      end
    elseif tok.t == "hold" then
      local b = open_bar()
      local last = b.ev[#b.ev]
      if not last then
        if v.last then err("'-' at the start of a bar; tie across the bar line with ~ instead")
        else err("'-' with no note before it") end
      elseif v.tie_open then
        err("'-' right after a tie")
      elseif last.kind == "rest" then
        err("'-' after a rest; write more 0s instead")
      elseif last.dotted then
        err("dotted note followed by '-'")
      elseif last.lines > 0 then
        err("'-' after a note shorter than one beat")
      else
        if v.pending then
          b.chords[#b.chords + 1] = { beat = b.pos, chord = v.pending.chord, src = v.pending.src, on_hold = true }
          v.pending = nil
        end
        last.units = last.units + 1
        last.holds = last.holds + 1
        b.pos = b.pos + 1
      end
    elseif tok.t == "tie" then
      if not v or not v.last or v.last.kind == "rest" then err("'~' must follow a note")
      else v.tie_open = v.last end
    else
      err("can't read '%s'", tok.v)
    end
  end

  -- close every voice
  for _, vv in ipairs(voices) do
    v = vv
    if v.cur and #v.cur.ev > 0 then close_bar("single")
    elseif v.cur and v.cur.ending then err("ending mark with no bar after it") end
    if v.pending then err("chord [%s] has no note after it", v.pending.src) end
    if v.tie_open then err("tie at the end with no note after it") end
  end
  v = nil

  if #voices == 0 then
    errs[#errs + 1] = { msg = "empty melody", bar = 1 }
    return nil, errs, warns
  end
  if byname[""] and #voices > 1 then
    errs[#errs + 1] = { msg = "mix of named (S:) and unnamed voices", bar = 1 }
  end

  -- every voice: same bar count, each bar full
  local nbars = #voices[1].bars
  for _, vv in ipairs(voices) do
    if #vv.bars ~= nbars then
      errs[#errs + 1] = { msg = string.format("voice %s has %d bars but voice %s has %d",
        vv.name, #vv.bars, voices[1].name, nbars), bar = math.min(#vv.bars, nbars) + 1, voice = vv.name }
    end
    for bi, b in ipairs(vv.bars) do
      if math.abs(b.pos - time.beats) > 1e-6 then
        errs[#errs + 1] = { msg = string.format("bar adds up to %s, but %s needs %d",
          fmt(b.pos), time.label, time.beats), bar = bi, voice = vv.name ~= "" and vv.name or nil }
      end
    end
  end

  -- chords from all voices, pinned to beats; one chord per beat
  local bars = {}
  for bi = 1, nbars do
    local first = voices[1].bars[bi]
    local chords, at = {}, {}
    for _, vv in ipairs(voices) do
      local b = vv.bars[bi]
      for _, c in ipairs(b and b.chords or {}) do
        local key = fmt(c.beat)
        if at[key] and at[key].src ~= c.src then
          errs[#errs + 1] = { msg = string.format("two different chords on beat %s: [%s] and [%s]",
            fmt(c.beat + 1), at[key].src, c.src), bar = bi }
        elseif not at[key] then
          at[key] = c
          chords[#chords + 1] = c
        end
      end
    end
    table.sort(chords, function(a, b) return a.beat < b.beat end)
    bars[bi] = { left = first.left, right = first.right, ending = first.ending, chords = chords }
  end

  -- ending spans, as in \bars
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
      spans[#spans + 1] = { n = b.ending, from = i, to = j, closed = (r == "repeat-end" or r == "repeat-both") }
    end
  end

  return { voices = voices, bars = bars, spans = spans, time = time }, errs, warns
end

---------------------------------------------------------------------------
-- Layout: positions only, no TeX.
---------------------------------------------------------------------------

local function each_event(tree, fn)
  for vi, vv in ipairs(tree.voices) do
    for bi, b in ipairs(vv.bars) do
      for ei, e in ipairs(b.ev) do fn(e, vi, bi, ei) end
    end
  end
end

-- Height above an event's top digit where a tie starts, clear of its octave dots.
local function tie_lift(e)
  local top = e.pitches and e.pitches[#e.pitches]
  if top and top.oct > 0 then return DOT_GAP + (top.oct - 1) * DOT_STEP + DOT_R + 1.5 end
  return 2
end

local STACK = DIGIT_H + STACK_GAP -- baseline step between stacked digits

-- Rough width of a chord label, in units of the chord font's digit width:
-- root digits and accidentals at full size, superscripts at about 0.6.
local function chord_width(c, cw)
  local w = cw * (1 + (c.chord.acc ~= 0 and 0.5 or 0) + (c.chord.minor and 0.85 or 0))
  local sup = c.src:gsub("^<?[b#]?%d", ""):gsub("/.*$", "")
  if c.chord.minor then sup = sup:gsub("^[m%-]", "") end
  w = w + #sup * cw * 0.6
  if c.chord.bass then w = w + cw * (1.5 + (c.chord.bass.acc ~= 0 and 0.5 or 0)) end
  return w
end

-- opts: width (pt), per (bars per row), repeatchords (bool),
--       digit_w and digit_h (pt, measured in the melody font),
--       chord_w (pt, a digit in the melody chord font)
function M.layout(tree, opts)
  DIGIT_W = opts.digit_w or 8
  DIGIT_H = opts.digit_h or 11.6
  STACK = DIGIT_H + STACK_GAP
  local time = tree.time
  local labeled = #tree.voices > 1
  local gutter = labeled and LABEL_W or 0
  local avail = (opts.width or 240) - gutter

  local level = 0
  each_event(tree, function(e) if e.lines > level then level = e.lines end end)
  local scale = DIGIT_W / 8 -- the grid sizes were set for 8pt digits
  local umin = U_MIN[level] * scale
  -- each chord label must clear the next chord (or the next bar's first beat)
  local cw = opts.chord_w or 8
  for _, b in ipairs(tree.bars) do
    for i, c in ipairs(b.chords) do
      local nxt = b.chords[i + 1]
      local need = chord_width(c, cw) + CHORD_PAD
      if nxt then
        umin = math.max(umin, need / (nxt.beat - c.beat))
      else
        umin = math.max(umin, (need - LEAD) / (time.beats - c.beat))
      end
    end
  end
  local n = math.max(1, opts.per or 4)
  while n > 1 and n * (time.beats * umin + LEAD) > avail do n = n - 1 end
  local U = math.max(umin, math.min(math.max(U_MAX * scale, umin), (avail / n - LEAD) / time.beats))
  local BW = time.beats * U + LEAD

  local rows = {}
  for r = 1, #tree.bars, n do
    local row = { first = r, last = math.min(r + n - 1, #tree.bars), U = U, gutter = gutter }
    -- a bar opening with a repeat sign gets extra lead-in for the dots
    row.barx, row.barw, row.lead = {}, {}, {}
    local x = gutter
    for bi = row.first, row.last do
      local l = tree.bars[bi].left
      row.lead[bi] = LEAD + ((l == "repeat-start" or l == "repeat-both") and REPEAT_PAD or 0)
      row.barx[bi], row.barw[bi] = x, BW - LEAD + row.lead[bi]
      x = x + row.barw[bi]
    end
    row.width = x + 6

    -- vertical extents per voice
    local y = 0
    row.voices = {}
    for vi, vv in ipairs(tree.voices) do
      local up, down = 0, 0
      for bi = row.first, row.last do
        for _, e in ipairs(vv.bars[bi].ev) do
          local u, d = 0, LINE_Y0 + e.lines * LINE_STEP
          if e.pitches then
            local top, low = e.pitches[#e.pitches], e.pitches[1]
            u = (#e.pitches - 1) * STACK + math.max(top.oct, 0) * DOT_STEP + (top.oct > 0 and DOT_GAP or 0)
            d = d + math.max(-low.oct, 0) * DOT_STEP
          end
          if e.tie_to or e.tie_from then
            u = math.max(u, (e.pitches and (#e.pitches - 1) * STACK or 0) + tie_lift(e) + TIE_H)
          end
          up, down = math.max(up, u), math.max(down, d)
        end
      end
      if vi > 1 then y = y - row.voices[vi - 1].down - VOICE_GAP - DIGIT_H - up end
      row.voices[vi] = { y = y, up = up, down = down }
    end

    local top = DIGIT_H + row.voices[1].up
    row.has_chords = false
    for bi = row.first, row.last do
      if #tree.bars[bi].chords > 0 then row.has_chords = true end
    end
    if row.has_chords then
      row.chord_y = top + CHORD_GAP
      top = row.chord_y + CHORD_H
    end
    for _, sp in ipairs(tree.spans) do
      if sp.to >= row.first and sp.from <= row.last then
        row.end_lo = top + 3
        row.end_hi = row.end_lo + END_RISE
        top = row.end_hi + 2
      end
    end
    local lastv = row.voices[#row.voices]
    row.top = top + 2
    row.bottom = lastv.y - lastv.down - DOT_R - 2
    row.bar_top = DIGIT_H + 3
    row.bar_bot = lastv.y - 4
    rows[#rows + 1] = row
  end

  -- event positions
  each_event(tree, function(e, vi, bi)
    for _, row in ipairs(rows) do
      if bi >= row.first and bi <= row.last then
        e.row = row
        e.x = row.barx[bi] + row.lead[bi] + e.start * U
        e.y = row.voices[vi].y
      end
    end
  end)
  for bi, b in ipairs(tree.bars) do
    for _, row in ipairs(rows) do
      if bi >= row.first and bi <= row.last then
        for _, c in ipairs(b.chords) do c.x = row.barx[bi] + row.lead[bi] + c.beat * U end
      end
    end
  end

  -- repeated chords hidden on request
  local prev
  for _, b in ipairs(tree.bars) do
    for _, c in ipairs(b.chords) do
      c.hidden = (opts.repeatchords == false) and prev == c.src or nil
      prev = c.src
    end
  end

  return rows
end

---------------------------------------------------------------------------
-- Emitter
---------------------------------------------------------------------------

local function pt(v) return fmt(v) .. "pt" end
local function xy(x, y) return "(" .. pt(x) .. "," .. pt(y) .. ")" end

local ACC = { b = "\\scalebox{0.8}{\\nnsFlat}", ["#"] = "\\scalebox{0.8}{\\nnsSharp}" }

local function emit_row(row, tree, out)
  out("\\nnsRowBegin\\begin{tikzpicture}")
  out("\\path " .. xy(0, row.bottom) .. " rectangle " .. xy(row.width, row.top) .. ";")

  -- voice labels
  if row.gutter > 0 then
    for vi, vv in ipairs(tree.voices) do
      out(string.format("\\node[nnsmlabel] at %s {%s};", xy(0, row.voices[vi].y), vv.name))
    end
  end

  -- bar lines: row start, then each bar's right edge
  local function vline(x, style)
    out(string.format("\\draw[%s] %s -- %s;", style, xy(x, row.bar_bot), xy(x, row.bar_top)))
  end
  local function dots(x)
    for _, rv in ipairs(row.voices) do
      local mid = rv.y + DIGIT_H / 2
      out(string.format("\\fill %s circle[radius=1.2pt]; \\fill %s circle[radius=1.2pt];",
        xy(x, mid - 3), xy(x, mid + 3)))
    end
  end
  local function start_sign(x) vline(x + 1, "nnsthickbar"); vline(x + 4.5, "nnsbarline"); dots(x + 7.6) end
  local function end_sign(x) dots(x - 7.6); vline(x - 4.5, "nnsbarline"); vline(x - 1, "nnsthickbar") end
  local function boundary(x, style, where)
    if style == "double" then vline(x - 3, "nnsbarline"); vline(x, "nnsbarline")
    elseif style == "repeat-start" and where ~= "end" then start_sign(x)
    elseif style == "repeat-end" and where ~= "start" then end_sign(x)
    elseif style == "repeat-both" then
      if where ~= "start" then end_sign(x) end
      if where ~= "end" then start_sign(x) end
    else vline(x, "nnsbarline") end
  end
  boundary(row.barx[row.first], tree.bars[row.first].left, "start")
  for bi = row.first, row.last do
    boundary(row.barx[bi] + row.barw[bi], tree.bars[bi].right, bi == row.last and "end" or "mid")
  end

  -- chords
  if row.has_chords then
    for bi = row.first, row.last do
      for _, c in ipairs(tree.bars[bi].chords) do
        if not c.hidden then
          out(string.format("\\node[nnsmchord] at %s {%s};", xy(c.x, row.chord_y), nns.chord_tex(c.chord)))
        end
      end
    end
  end

  -- endings
  for _, sp in ipairs(tree.spans) do
    if sp.to >= row.first and sp.from <= row.last then
      local starts, ends = sp.from >= row.first, sp.to <= row.last
      local x1 = starts and row.barx[sp.from] + 3 or row.barx[row.first]
      local z = math.min(sp.to, row.last); local x2 = row.barx[z] + row.barw[z] - 3
      local p = starts and (xy(x1, row.end_lo) .. " -- ") or ""
      p = p .. xy(x1, row.end_hi) .. " -- " .. xy(x2, row.end_hi)
      if ends and sp.closed then p = p .. " -- " .. xy(x2, row.end_lo) end
      out("\\draw[nnsending] " .. p .. ";")
      if starts then
        out(string.format("\\node[nnsendinglabel] at %s {%d.};", xy(x1 + 1, row.end_hi), sp.n))
      end
    end
  end

  -- events
  local ties = {}
  for vi, vv in ipairs(tree.voices) do
    for bi = row.first, row.last do
      local b = vv.bars[bi]
      local beams, open = {}, {}
      for ei, e in ipairs(b.ev) do
        local id = string.format("m%d-%d-%d", vi, bi, ei)
        e.id = id .. "-1"
        if e.kind == "rest" then
          out(string.format("\\node[nnsmnote] (%s) at %s {0};", e.id, xy(e.x, e.y)))
        else
          for pi, p in ipairs(e.pitches) do
            local pid = id .. "-" .. pi
            out(string.format("\\node[nnsmnote] (%s) at %s {%d};", pid, xy(e.x, e.y + (pi - 1) * STACK), p.deg))
            if p.acc ~= "" then
              out(string.format("\\node[nnsmacc] at ([xshift=-0.3pt]%s.base west) {%s};", pid, ACC[p.acc]))
            end
            for k = 1, math.max(p.oct, 0) do
              out(string.format("\\fill[nnsmdot] ([yshift=%s]%s.north) circle[radius=%s];",
                pt(DOT_GAP + (k - 1) * DOT_STEP), pid, pt(DOT_R)))
            end
            -- the lowest digit's dots go under its underlines
            local below = DOT_GAP
            if pi == 1 and e.lines > 0 then below = LINE_Y0 + (e.lines - 1) * LINE_STEP + DOT_GAP end
            for k = 1, math.max(-p.oct, 0) do
              out(string.format("\\fill[nnsmdot] ([yshift=%s]%s.south) circle[radius=%s];",
                pt(-(below + (k - 1) * DOT_STEP)), pid, pt(DOT_R)))
            end
          end
          e.top_id = id .. "-" .. #e.pitches
        end
        if e.dotted then
          out(string.format("\\fill[nnsmdot] ([shift={(2.4pt,3.6pt)}]%s.base east) circle[radius=1.2pt];", e.id))
        end
        for h = 1, e.holds do
          local x = e.x + h * row.U + (DIGIT_W - DASH_W) / 2
          out(string.format("\\draw[nnsmdash] %s -- ++(%s,0);", xy(x, e.y + DIGIT_H * 0.42), pt(DASH_W)))
        end
        -- underlines: consecutive short notes inside one beat share a line
        local beat = math.floor(e.start + 1e-9)
        for lv = 1, 2 do
          local g = open[lv]
          if lv > e.lines then
            open[lv] = nil
          elseif g and g.beat == beat then
            g.to = e.id
          else
            open[lv] = { lv = lv, beat = beat, from = e.id, to = e.id }
            beams[#beams + 1] = open[lv]
          end
        end
        if e.tie_to then ties[#ties + 1] = e end
      end
      for _, g in ipairs(beams) do
        local dy = pt(-(LINE_Y0 + (g.lv - 1) * LINE_STEP))
        out(string.format("\\draw[nnsmbeam] ([yshift=%s]%s.south west) -- ([yshift=%s]%s.south east);",
          dy, g.from, dy, g.to))
      end
    end
  end

  -- ties: whole arcs inside the row, half arcs across a row break
  local function tie_id(e) return e.top_id or e.id end
  local function tie_end(e, dx)
    return string.format("([shift={(%s,%s)}]%s.north)", pt(dx), pt(tie_lift(e)), tie_id(e))
  end
  -- height of a half arc's open end, above the note it leaves or reaches
  local function crest(e)
    return e.y + (e.pitches and (#e.pitches - 1) * STACK or 0) + DIGIT_H + tie_lift(e) + TIE_H - 2
  end
  for _, a in ipairs(ties) do
    local z = a.tie_to
    if z.row == row then
      out(string.format("\\draw[nnsmtie] %s to[out=35,in=145] %s;", tie_end(a, 1), tie_end(z, -1)))
    else
      out(string.format("\\draw[nnsmtie] %s to[out=35,in=180] %s;", tie_end(a, 1),
        xy(row.barx[row.last] + row.barw[row.last] - 2, crest(a))))
    end
  end
  for vi, vv in ipairs(tree.voices) do
    for bi = row.first, row.last do
      for _, e in ipairs(vv.bars[bi].ev) do
        if e.tie_from and e.tie_from.row ~= row then
          out(string.format("\\draw[nnsmtie] %s to[out=0,in=145] %s;",
            xy(row.barx[row.first] + 2, crest(e)), tie_end(e, -1)))
        end
      end
    end
  end

  out("\\end{tikzpicture}\\nnsRowEnd")
end

---------------------------------------------------------------------------
-- Entry point for \melody
---------------------------------------------------------------------------

-- opts: time ("6/8"), per ("4"), width ("240.0pt"), repeatchords ("true"),
--       digit_w, digit_h ("8.0pt")
function M.render(src, opts)
  src = src:gsub("##", "#")
  local time = parse_time(opts.time)
  local tree, errs, warns = M.parse(src, time)
  local base = nns.state.bar
  local function where(e)
    return string.format("bar %d%s of section '%s'", base + e.bar,
      e.voice and (", voice " .. e.voice) or "", nns.state.section)
  end
  for _, w in ipairs(warns) do
    texio.write_nl("term and log", "nns warning: " .. w.msg .. " in " .. where(w))
  end
  if #errs > 0 then
    for _, e in ipairs(errs) do
      tex.error("nns: " .. e.msg .. " in " .. where(e), {
        "The \\melody string could not be understood. See README.md for the",
        "melody notation (degrees 1-7, ' and , for octaves, / for eighths).",
      })
    end
    return
  end
  nns.claim_section("melody")
  local rows = M.layout(tree, {
    width = tonumber((opts.width or ""):match("[%d.]+")) or 240,
    per = tonumber(opts.per) or 4,
    repeatchords = opts.repeatchords ~= "false",
    digit_w = tonumber((opts.digit_w or ""):match("[%d.]+")),
    digit_h = tonumber((opts.digit_h or ""):match("[%d.]+")),
    chord_w = tonumber((opts.chord_w or ""):match("[%d.]+")),
  })
  for _, row in ipairs(rows) do emit_row(row, tree, nns.out) end
  nns.state.bar = base + #tree.bars
end

M._lex = lex

return M
