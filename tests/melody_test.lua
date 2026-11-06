-- Unit tests for src/lua/nnsmelody.lua. Run: texlua tests/melody_test.lua
-- (or `make test`). Exercises parse, validation and layout; no TeX needed.

local root = arg[0]:match("^(.*)/tests/") or "."
package.path = root .. "/src/lua/?.lua;" .. package.path

local mel = require("nnsmelody")

local failures, count = 0, 0
local function check(name, cond, detail)
  count = count + 1
  if not cond then
    failures = failures + 1
    print("FAIL " .. name .. (detail and (": " .. detail) or ""))
  end
end

local function parse(src, time)
  return mel.parse(src, mel.parse_time(time or "4/4"))
end

local function has(list, pat)
  for _, e in ipairs(list) do if e.msg:find(pat) then return true end end
  return false
end

local function msgs(list)
  local t = {}
  for _, e in ipairs(list) do t[#t + 1] = e.msg end
  return table.concat(t, " | ")
end

local function ok(name, src, time)
  local tree, errs, warns = parse(src, time)
  check(name .. " parses", tree and #errs == 0, msgs(errs))
  return tree, warns
end

local function fails(name, src, pat, time)
  local _, errs = parse(src, time)
  check(name .. " is an error", has(errs, pat), "got: " .. msgs(errs))
end

local function warns_(name, src, pat)
  local tree, errs, warns = parse(src)
  check(name .. " parses", #errs == 0, msgs(errs))
  check(name .. " warns", has(warns, pat), "got: " .. msgs(warns))
end

---------------------------------------------------------------- spec examples

local ex1 = "[1] 3 3 4 5 | [5] 5 4 3 2 | [1] 1 1 2 3 | [5] 3. 2/ 2 - ||"
local ex2 = "[1] 5, 1 3 5 | [4] 1' b7 6 0 | [5] 5/ 5/ 3 3 3 ~ | [1] 3 - - - ||"
local ex3 = "S: [1] 3 - 5/ 3/ 1 | [4] 6 - - 0 || B: 1, 5, 1 - | 4, - 4, - ||"
local ex4 = "S: [1] (1 3 5) - - - | [5] (2 5 7) - - - || B: 1, 5, 1 - | 5, - 5, - ||"
local ex5 = "[1] 5/ 5// 5// 3 3 3 ||"

do
  local t = ok("example 1", ex1)
  local b4 = t.voices[1].bars[4]
  check("ex1 dotted quarter", b4.ev[1].units == 1.5 and b4.ev[1].dotted)
  check("ex1 eighth", b4.ev[2].units == 0.5 and b4.ev[2].lines == 1)
  check("ex1 hold folded", b4.ev[3].units == 2 and b4.ev[3].holds == 1)
  check("ex1 chords per bar", #t.bars[1].chords == 1 and t.bars[1].chords[1].beat == 0)
  check("ex1 final bar", t.bars[4].right == "double")
end

do
  local t = ok("example 2", ex2)
  local b = t.voices[1].bars
  check("ex2 low octave", b[1].ev[1].pitches[1].oct == -1)
  check("ex2 high octave", b[2].ev[1].pitches[1].oct == 1)
  check("ex2 flat", b[2].ev[2].pitches[1].acc == "b")
  check("ex2 rest", b[2].ev[4].kind == "rest")
  check("ex2 tie across bar", b[3].ev[5].tie_to == b[4].ev[1] and b[4].ev[1].tie_from == b[3].ev[5])
  check("ex2 whole note", b[4].ev[1].units == 4 and b[4].ev[1].holds == 3)
end

do
  local t = ok("example 3", ex3)
  check("ex3 two voices", #t.voices == 2 and t.voices[1].name == "S" and t.voices[2].name == "B")
  check("ex3 bass bar 2", #t.voices[2].bars[2].ev == 2)
end

do
  local t = ok("example 4", ex4)
  local s = t.voices[1].bars[1].ev[1]
  check("ex4 stack", s.kind == "stack" and #s.pitches == 3 and s.units == 4)
  local u = ok("unsorted stack", "(5 1 3) - - - ||").voices[1].bars[1].ev[1]
  check("stack sorted low to high", u.pitches[1].deg == 1 and u.pitches[3].deg == 5)
  local v = ok("stack with octaves", "(1, 5, 3)/ 0/ 0 0 0 ||").voices[1].bars[1].ev[1]
  check("stack eighth", v.units == 0.5 and v.pitches[1].deg == 1 and v.pitches[3].deg == 3)
end

do
  local t = ok("example 5", ex5)
  local e = t.voices[1].bars[1].ev
  check("ex5 sixteenths", e[2].units == 0.25 and e[2].lines == 2 and e[3].units == 0.25)
end

---------------------------------------------------------------- time signatures

do
  local t = ok("6/8 bare notes are eighths", "[1] 1 2 3 4 5 6 | 5 - - 3 - - ||", "6/8")
  check("6/8 hold", t.voices[1].bars[2].ev[1].units == 3)
  fails("6/8 bar of 4", "1 2 3 4 ||", "6/8 needs 6", "6/8")
  ok("3/4", "1 2 3 | 5 - - ||", "3/4")
end

---------------------------------------------------------------- validation table

fails("bar too short", "1 2 3 ||", "adds up to 3")
fails("bar too long", "1 2 3 4 5 ||", "adds up to 5")
fails("voices with different bar counts", "S: 1 2 3 4 | 5 6 7 1' || B: 1 - - - ||", "has 1 bars")
fails("trailing chord", "1 2 3 4 [5] | 5 - - - ||", "no note")
fails("two chords on one beat", "S: [1] 1 2 3 4 || B: [4] 1, - - - ||", "two different chords")
fails("dotted note then hold", "1. 2/ 3. - ||", "dotted note followed")
fails("hold with no note", "- 1 2 3 ||", "no note before")
fails("hold at bar start", "1 2 3 4 | - 1 2 3 ||", "start of a bar")
fails("three octave marks", "1''' 2 3 4 ||", "two octaves")
fails("degree 8", "8 2 3 4 ||", "1%-7")
fails("rest with octave", "0' 2 3 4 ||", "just 0")
fails("bad token", "1 2 x 4 ||", "can't read 'x'")
fails("unclosed chord", "[1 2 3 4 ||", "can't read")
fails("unknown chord", "[9] 1 2 3 4 ||", "can't read chord")
fails("push in melody chord", "[<5] 1 2 3 4 ||", "pushes")
fails("tie at end", "1 2 3 4 ~ ||", "tie at the end")
fails("hold after rest", "0 - 1 2 ||", "after a rest")
fails("mixed named and unnamed", "1 2 3 4 || S: 1 2 3 4 ||", "mix of named")
warns_("tie between different pitches", "1 2 3 4 ~ | 5 - - - ||", "different pitches")
warns_("duplicate pitch in stack", "(1 3 3) - - - ||", "duplicate pitch")

do
  local t = ok("same chord from two voices", "S: [1] 1 2 3 4 || B: [1] 1, - - - ||")
  check("chord collected once", #t.bars[1].chords == 1)
end

do
  local t = ok("chord on a hold", "[1] 1 [4] - [5] 5 - ||")
  local c = t.bars[1].chords
  check("chord on hold gets its beat", #c == 3 and c[2].beat == 1 and c[3].beat == 2)
end

---------------------------------------------------------------- endings and repeats

do
  local t = ok("endings", "|: [1] 1 2 3 4 | [1. [5] 5 - - - :|[2. [1] 1 - - - ||")
  check("repeat start", t.bars[1].left == "repeat-start")
  check("two ending spans", #t.spans == 2 and t.spans[1].closed and not t.spans[2].closed)
  check("ending 2 covers bar 3", t.spans[2].from == 3 and t.spans[2].to == 3)
end

---------------------------------------------------------------- layout

do
  local t = ok("layout two voices", ex3)
  local rows = mel.layout(t, { width = 240, per = 4 })
  -- spec acceptance 5: same start beat, same x, in every voice
  local s, b = t.voices[1].bars, t.voices[2].bars
  check("beat 1 aligned", s[1].ev[1].x == b[1].ev[1].x)
  check("beat 3 aligned", s[1].ev[2].x == b[1].ev[3].x)    -- 5/ starts on beat 3, bass 1 on beat 3
  check("bar 2 beat 3 aligned", s[2].ev[1].x < b[2].ev[2].x and b[2].ev[2].x - b[2].ev[1].x == 2 * rows[1].U)
  check("voices stacked", t.voices[1].bars[1].ev[1].y > t.voices[2].bars[1].ev[1].y)
  -- spec acceptance 6: a chord written on any voice is drawn once, above the top voice
  local t2 = ok("chord on lower voice", "S: 1 2 3 4 || B: [4] 1, - - - ||")
  local r2 = mel.layout(t2, { width = 240, per = 4 })
  check("bass chord drawn above top voice", #t2.bars[1].chords == 1 and r2[1].chord_y > 0)
end

do
  local t = ok("row breaking", ex1)
  local narrow = mel.layout(t, { width = 240, per = 4 })
  check("two-column width fits 2 bars of 4/4", #narrow == 2 and narrow[1].last == 2, "rows=" .. #narrow)
  local wide = mel.layout(t, { width = 520, per = 4 })
  check("one-column width fits 4 bars", #wide == 1)
  local sixteen = ok("sixteenths widen the grid", ex5)
  local r = mel.layout(sixteen, { width = 520, per = 4 })
  check("sixteenth grid wider", r[1].U >= 40)
  local t68 = ok("6/8 layout", "1 2 3 4 5 6 | 1 - - 1 - - ||", "6/8")
  local r68 = mel.layout(t68, { width = 240, per = 4 })
  check("6/8 fits 2 bars in a column", r68[1].last == 2, "last=" .. r68[1].last)
end

do
  local t = ok("chords one beat apart", "[1] 1 - [1sus] 0 [1] 0 ||")
  local r = mel.layout(t, { width = 240, per = 4, digit_w = 6.5, chord_w = 8 })
  local c = t.bars[1].chords
  check("chord labels don't collide", (c[3].x - c[2].x) >= 8 + 3 * 8 * 0.6 + 4 - 1e-6,
    string.format("gap %.1f", c[3].x - c[2].x))
end

do
  local t = ok("repeated chords", "[1] 1 2 [1] 3 4 | [5] 5 - - - ||")
  mel.layout(t, { width = 240, per = 4, repeatchords = false })
  local c = t.bars[1].chords
  check("repeated chord hidden", not c[1].hidden and c[2].hidden and not t.bars[2].chords[1].hidden)
end

do
  local t = ok("tie across a row break", "1 2 3 4 | 5 6 7 1' ~ | 1' - - - ||")
  mel.layout(t, { width = 240, per = 4 })
  local a, z = t.voices[1].bars[2].ev[4], t.voices[1].bars[3].ev[1]
  check("tied notes in different rows", a.row ~= z.row)
end

print(string.format("%d checks, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
