-- ui.lua — retro pixel front end (desktop LÖVE only; LoveDOS keeps the plain
-- text screen in main.lua).
--
-- Everything is drawn 1:1 onto a 640x400 canvas (VGA 80x50 text-mode
-- geometry) with an 8x8 bitmap font and the 16-colour VGA palette, then shown
-- at an integer scale with nearest-neighbour filtering (optional scanlines).
--
-- The display follows what is *heard*: every player tick pushes a snapshot
-- stamped with its output frame, and update() shows the latest snapshot at the
-- current playback position.  Scope and spectrum read the output ring buffer
-- at that position too.

local ffi       = require("ffi")
local utf8      = require("utf8")
local pixelfont = require("pixelfont")

local ui = {}
local W, H = 640, 400
ui.W, ui.H = W, H

local lg = love.graphics
local floor, sin, max, min = math.floor, math.sin, math.max, math.min

-- ── VGA palette ──────────────────────────────────────────────────────────────
local C = {
    black    = {0, 0, 0},          blue     = {0, 0, 2/3},
    green    = {0, 2/3, 0},        cyan     = {0, 2/3, 2/3},
    red      = {2/3, 0, 0},        magenta  = {2/3, 0, 2/3},
    brown    = {2/3, 1/3, 0},      lgray    = {2/3, 2/3, 2/3},
    dgray    = {1/3, 1/3, 1/3},    lblue    = {1/3, 1/3, 1},
    lgreen   = {1/3, 1, 1/3},      lcyan    = {1/3, 1, 1},
    lred     = {1, 1/3, 1/3},      lmagenta = {1, 1/3, 1},
    yellow   = {1, 1, 1/3},        white    = {1, 1, 1},
}
-- Dimmed variant of each colour (rows already played).
local DIM = {
    [C.white] = C.lgray, [C.lgray] = C.dgray, [C.dgray] = C.dgray, [C.lcyan] = C.cyan,
    [C.lgreen] = C.green, [C.lmagenta] = C.magenta, [C.yellow] = C.brown, [C.lred] = C.red,
}

-- ── Drawing helpers ──────────────────────────────────────────────────────────
local function color(c) lg.setColor(c[1], c[2], c[3], 1) end
local function rect(x, y, w, h, c) color(c); lg.rectangle("fill", x, y, w, h) end
local function frame(x, y, w, h, c)
    rect(x, y, w, 1, c); rect(x, y + h - 1, w, 1, c)
    rect(x, y, 1, h, c); rect(x + w - 1, y, 1, h, c)
end
local function text(s, x, y, c) color(c); lg.print(s, x, y) end
local function shadow(s, x, y, c, scale)
    scale = scale or 1
    color(C.black); lg.print(s, x + scale, y + scale, 0, scale, scale)
    color(c);       lg.print(s, x, y, 0, scale, scale)
end
local function len(s) return utf8.len(s) or #s end
local function fit(s, n)                     -- keep the end of long strings
    local l = len(s)
    if l <= n then return s end
    return "..." .. s:sub(utf8.offset(s, l - n + 4) or -(n - 3))  -- cut on a character boundary
end
local function label(s, x, y)                -- caption cut into a panel border
    rect(x + 6, y - 4, len(s) * 8 + 4, 8, C.black)
    text(s, x + 8, y - 4, C.lcyan)
end
-- MOD texts are raw bytes (often CP437 or garbage): keep printable ASCII only
local function ascii(s)
    return (s:gsub("[^\32-\126]", " "))
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ── Canvas / scaling ─────────────────────────────────────────────────────────
local font, canvas
local scale, ox, oy = 1, 0, 0
local ring, RING, sampleRate

function ui.load(ringBuffer, ringSize, rate)
    ring, RING, sampleRate = ringBuffer, ringSize, rate
    lg.setDefaultFilter("nearest", "nearest")
    lg.setLineStyle("rough")
    font   = pixelfont.new()
    canvas = lg.newCanvas(W, H)
    canvas:setFilter("nearest", "nearest")
    lg.setFont(font)
    ui.resize(lg.getDimensions())
    ui.initSpectrum()
end

function ui.resize(w, h)
    scale = max(1, floor(min(w / W, h / H)))
    ox, oy = floor((w - W * scale) / 2), floor((h - H * scale) / 2)
end

-- Window → canvas coordinates.
function ui.toCanvas(x, y)
    return floor((x - ox) / scale), floor((y - oy) / scale)
end

-- ── Snapshots (display state per tick) ───────────────────────────────────────
local snaps, head, cur = {}, 0, nil
local vu, vuPeak, vuHold = {}, {}, {}

-- New song / rewind: forget pending snapshots, show `snap` (may be nil).
function ui.reset(pos, snap)
    snaps, head, cur = {}, 0, snap
    vu, vuPeak, vuHold = {}, {}, {}
    for i = 1, 32 do vu[i], vuPeak[i], vuHold[i] = 0, 0, 0 end
end

function ui.pushTick(snap)
    snaps[#snaps + 1] = snap
end

function ui.current() return cur end

-- ── Spectrum analyser (radix-2 FFT over the ring buffer) ─────────────────────
local N = 1024
local re, im = ffi.new("double[?]", N), ffi.new("double[?]", N)
local win    = ffi.new("double[?]", N)
local rev    = ffi.new("int32_t[?]", N)
local cosT, sinT = ffi.new("double[?]", N / 2), ffi.new("double[?]", N / 2)
for i = 0, N - 1 do
    win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1))
    local r, x = 0, i
    for _ = 1, 10 do r = r * 2 + x % 2; x = floor(x / 2) end
    rev[i] = r
end
for i = 0, N / 2 - 1 do
    cosT[i], sinT[i] = math.cos(2 * math.pi * i / N), math.sin(2 * math.pi * i / N)
end

local function fft()
    for i = 0, N - 1 do
        local j = rev[i]
        if j > i then re[i], re[j] = re[j], re[i] end
        im[i] = 0
    end
    local size = 2
    while size <= N do
        local half, step = size / 2, N / size
        for i = 0, N - 1, size do
            for j = 0, half - 1 do
                local wr, wi = cosT[j * step], -sinT[j * step]
                local a, b = i + j, i + j + half
                local tr = re[b] * wr - im[b] * wi
                local ti = re[b] * wi + im[b] * wr
                re[b], im[b] = re[a] - tr, im[a] - ti
                re[a], im[a] = re[a] + tr, im[a] + ti
            end
        end
        size = size * 2
    end
end

local NBARS = 32
local bandLo, bandHi = {}, {}
local bars, barPeak, barHold = {}, {}, {}

function ui.initSpectrum()
    for b = 1, NBARS do
        local f0 = 50 * (14000 / 50) ^ ((b - 1) / NBARS)
        local f1 = 50 * (14000 / 50) ^ (b / NBARS)
        bandLo[b] = max(1, floor(f0 * N / sampleRate))
        bandHi[b] = max(bandLo[b], floor(f1 * N / sampleRate))
        bars[b], barPeak[b], barHold[b] = 0, 0, 0
    end
end

local function updateSpectrum(dt, playPos)
    local start = playPos - N
    for i = 0, N - 1 do
        local idx = start + i
        re[i] = idx >= 0 and ring[idx % RING] / 32768 * win[i] or 0
    end
    fft()
    local ref = 20 * math.log10(N / 4)          -- full-scale sine → 0 dB
    for b = 1, NBARS do
        local m = 0
        for k = bandLo[b], bandHi[b] do
            local p = re[k] * re[k] + im[k] * im[k]
            if p > m then m = p end
        end
        local db = 10 * math.log10(m + 1e-12) - ref
        local v = math.max(0, math.min(1, (db + 66) / 66))
        bars[b] = max(v, bars[b] - dt * 1.8)
        if bars[b] >= barPeak[b] then barPeak[b], barHold[b] = bars[b], 0.6
        else
            barHold[b] = barHold[b] - dt
            if barHold[b] <= 0 then barPeak[b] = max(0, barPeak[b] - dt * 0.8) end
        end
    end
end

-- ── Per-frame update ─────────────────────────────────────────────────────────
local time = 0
local playPos = 0

function ui.update(dt, pos)
    time, playPos = time + dt, pos
    while snaps[head + 1] and snaps[head + 1].pos <= pos do
        head = head + 1
        local s = snaps[head]
        for i = 1, #s.hit do      -- a note-on kicks the meter, scaled by volume
            if s.hit[i] then vu[i] = max(vu[i] or 0, 0.25 + 0.75 * s.vol[i] / 64) end
        end
        cur = s
    end
    if head > 256 then                      -- drop consumed snapshots
        local rest = {}
        for i = head + 1, #snaps do rest[#rest + 1] = snaps[i] end
        snaps, head = rest, 0
    end
    for i = 1, #vu do
        vu[i] = max(0, vu[i] - dt * 1.1)
        if vu[i] >= vuPeak[i] then vuPeak[i], vuHold[i] = vu[i], 0.5
        else
            vuHold[i] = vuHold[i] - dt
            if vuHold[i] <= 0 then vuPeak[i] = max(0, vuPeak[i] - dt * 0.6) end
        end
    end
    updateSpectrum(dt, pos)
end

-- ── Panels ───────────────────────────────────────────────────────────────────
local RASTER = {
    { C.blue, C.lblue, C.lcyan, C.white, C.lcyan, C.lblue, C.blue },
    { C.red, C.lred, C.yellow, C.white, C.yellow, C.lred, C.red },
    { C.magenta, C.lmagenta, C.white, C.lmagenta, C.magenta },
    { C.green, C.lgreen, C.white, C.lgreen, C.green },
}

local function drawHeader(app)
    rect(0, 0, W, 32, C.black)
    lg.setScissor(0, 0, W, 32)
    for i, bar in ipairs(RASTER) do
        local y = floor(16 + sin(time * 1.3 + i * 1.7) * 13) - floor(#bar / 2)
        for j, c in ipairs(bar) do rect(0, y + j - 1, W, 1, c) end
    end
    lg.setScissor()
    shadow("MOD PLAYER", 12, 8, C.white, 2)
    shadow("by SiENcE.github.io", 180, 16, C.lcyan)
    local l1 = app.mixer and ("SOFTWARE MIXER" .. (app.interpolate and " +LERP" or ""))
                         or "LOVEDOS SOURCE LAYER"
    local l2 = "PROTRACKER REPLAY"
    if app.mod then
        local tag = ascii(app.mod.format)
        -- tags like "8CHN" / "16CH" already name the channel count
        local chans = tag:find("C[HN]") and "" or (" " .. app.mod.numChannels .. "CH")
        l2 = string.format("%s%s %d SMP", tag, chans, #app.mod.samples)
    end
    shadow(l1, W - 12 - len(l1) * 8, 7, C.yellow)
    shadow(l2, W - 12 - len(l2) * 8, 17, C.lcyan)
end

local function drawInfoBar(app)
    rect(0, 32, W, 16, C.blue)
    local s, m = cur, app.mod
    local icon, ic
    if not s or s.ended then icon, ic = "■", C.lred
    elseif app.playing then icon, ic = "▶", C.lgreen
    else icon, ic = "‖", C.yellow end
    local y = 36
    text(icon, 8, y, ic)
    local title = m and trim(ascii(m.name)) or ""
    if title == "" then title = app.songName end
    text(fit(title ~= "" and title or "NO SONG", 17), 24, y, C.white)
    if not (s and m) then return end
    local function field(x, name, value)
        text(name, x, y, C.lcyan)
        text(value, x + (len(name) + 1) * 8, y, C.white)
    end
    field(168, "ORD", string.format("%02d/%02d", s.order - 1, m.songLength))
    field(256, "PAT", string.format("%02d", s.pattern))
    field(320, "ROW", string.format("%02d", s.row - 1))
    field(384, "SPD", string.format("%02d", s.speed))
    field(448, "BPM", string.format("%03d", s.bpm))
    local secs = floor(s.time)
    text(string.format("%02d:%02d", floor(secs / 60), secs % 60), 528, y, C.yellow)
    if #app.tracks > 0 then
        text(string.format("%02d/%02d", app.track, #app.tracks), 584, y, C.lgray)
    end
end

local function drawScope(x, y, w, h)
    frame(x, y, w, h, C.blue)
    label("SCOPE", x, y)
    local mid = y + floor(h / 2)
    for px = x + 2, x + w - 3, 4 do rect(px, mid, 1, 1, C.dgray) end
    local span = (w - 4) * 2
    -- Trigger on a rising zero crossing for a steady picture.
    local start = playPos - span - 512
    for i = 0, 511 do
        local a, b = start + i, start + i + 1
        if a >= 0 and ring[a % RING] < 0 and ring[b % RING] >= 0 then start = a; break end
    end
    color(C.lgreen)
    local amp, prev = (h - 8) / 2, nil
    for i = 0, w - 5 do
        local idx = start + i * 2
        local v = idx >= 0 and ring[idx % RING] / 32768 or 0
        local py = mid - floor(max(-1, min(1, v * 1.6)) * amp + 0.5)
        local y0, y1 = py, py
        if prev then y0, y1 = min(py, prev), max(py, prev) end
        lg.rectangle("fill", x + 2 + i, y0, 1, y1 - y0 + 1)
        prev = py
    end
end

local function drawSpectrum(x, y, w, h)
    frame(x, y, w, h, C.blue)
    label("SPECTRUM", x, y)
    local base, segs = y + h - 4, floor((h - 10) / 3)
    for b = 1, NBARS do
        local bx = x + 4 + (b - 1) * 8
        local n = floor(bars[b] * segs + 0.5)
        for s = 0, n - 1 do
            local c = s < segs * 0.45 and C.lblue or (s < segs * 0.8 and C.lcyan or C.white)
            rect(bx, base - s * 3 - 2, 6, 2, c)
        end
        local pk = floor(barPeak[b] * segs + 0.5)
        if pk > 0 then rect(bx, base - pk * 3 - 2, 6, 1, C.yellow) end
    end
end

local function drawVU(app, x, y, w, h)
    frame(x, y, w, h, C.blue)
    label("CHANNELS", x, y)
    local n = app.mod and min(app.mod.numChannels, 32) or 4
    local slot = min(24, floor((w - 8) / n))      -- fewer channels: wider bars
    local bw = max(1, slot - (slot >= 8 and 4 or 1))
    local x0 = x + floor((w - n * slot) / 2) + floor((slot - bw) / 2)
    local base, segs = y + h - 14, floor((h - 22) / 3)
    for i = 1, n do
        local bx = x0 + (i - 1) * slot
        local lit = floor((vu[i] or 0) * segs + 0.5)
        for s = 0, segs - 1 do
            if s < lit then
                local c = s < segs * 0.6 and C.lgreen or (s < segs * 0.85 and C.yellow or C.lred)
                rect(bx, base - s * 3 - 2, bw, 2, c)
            elseif s % 2 == 0 then
                rect(bx + floor(bw / 2), base - s * 3 - 2, 1, 1, C.dgray)
            end
        end
        local pk = floor((vuPeak[i] or 0) * segs + 0.5)
        if pk > 0 then rect(bx, base - pk * 3 - 2, bw, 1, C.white) end
        local active = cur and cur.active[i]
        if slot >= 16 then
            local s = tostring(i)
            text(s, bx + floor((bw - len(s) * 8) / 2), y + h - 10, active and C.white or C.dgray)
        elseif slot >= 8 then
            text(tostring(i % 10), bx + floor((bw - 8) / 2), y + h - 10, active and C.white or C.dgray)
        end
    end
end

-- Effect colour by type: pitch green, volume magenta, song flow red, rest cyan.
local function fxColor(e, p)
    if e == 0 and p == 0 then return C.dgray end
    if e == 0xE then
        local sub = floor(p / 16)
        if sub == 0x6 or sub == 0xE then return C.lred end
        if sub >= 0x1 and sub <= 0x5 then return C.lgreen end
        if sub >= 0xA and sub <= 0xC then return C.lmagenta end
        return C.lcyan
    end
    if e == 0xB or e == 0xD or e == 0xF then return C.lred end
    if e <= 0x6 then return C.lgreen end      -- arpeggio, slides, vibrato (5/6 + vol slide)
    if e == 0x7 or e == 0xA or e == 0xC then return C.lmagenta end
    return C.lcyan                            -- 8 pan, 9 sample offset
end

-- Cell layouts, widest that fits: x offsets of note / instrument / effect
local LAYOUTS = {
    { maxCh = 6,  w = 88, ins = 32, fx = 56 },  -- "C-2 01 A0F"
    { maxCh = 8,  w = 72, ins = 24, fx = 40 },  -- "C-201A0F"
    { maxCh = 12, w = 48, ins = 24 },           -- "C-201"
    { maxCh = 18, w = 32 },                     -- "C-2"
}

local PAT_X, PAT_Y, ROWS, CUR = 44, 152, 27, 13

local function drawPattern(app)
    local m, s = app.mod, cur
    if not (m and s) then return end
    local pat = m.patterns[s.pattern]
    local L = LAYOUTS[#LAYOUTS]
    for _, l in ipairs(LAYOUTS) do
        if m.numChannels <= l.maxCh then L = l; break end
    end
    local nch = min(m.numChannels, L.maxCh)
    local cw = L.w

    -- channel header: number and current instrument
    for c = 1, nch do
        local x = PAT_X + (c - 1) * cw
        text(tostring(c), x, PAT_Y - 8, s.active[c] and C.yellow or C.dgray)
        if L.ins and cw >= 48 then
            local ins = s.instr[c]
            text(ins == 0 and "--" or string.format("%02X", ins), x + L.ins, PAT_Y - 8, C.brown)
        end
    end
    if nch < m.numChannels then
        text("+" .. (m.numChannels - nch), PAT_X + nch * cw, PAT_Y - 8, C.lred)
    end
    rect(16, PAT_Y - 1 + CUR * 8 - 1, W - 32, 10, C.blue)
    for c = 1, nch - 1 do
        local sx = PAT_X + c * cw - 5
        for yy = PAT_Y, PAT_Y + ROWS * 8 - 1, 2 do rect(sx, yy, 1, 1, C.dgray) end
    end

    local cursor = s.row - 1                    -- 0-based row being played
    for r = 0, ROWS - 1 do
        local row = cursor + r - CUR
        if row >= 0 and row <= 63 then
            local y = PAT_Y + r * 8
            local here, dim = r == CUR, r < CUR
            local function col(c) return (dim and DIM[c]) or c end
            local rc = here and C.white or (row % 16 == 0 and C.yellow or (row % 4 == 0 and C.lgray or C.dgray))
            text(string.format("%02d", row), 20, y, col(rc))
            local rowData = pat and pat[row + 1]
            if rowData then
                for c = 1, nch do
                    local cell = rowData[c]
                    local x = PAT_X + (c - 1) * cw
                    local name = cell.period > 0 and app.noteName(cell.period) or nil
                    text(name or "...", x, y, col(name and (here and C.yellow or C.white) or C.dgray))
                    if L.ins then
                        if cell.sample > 0 then
                            text(string.format("%02X", cell.sample), x + L.ins, y, col(C.yellow))
                        else
                            text("..", x + L.ins, y, col(C.dgray))
                        end
                    end
                    if L.fx then
                        local e, p = cell.effect, cell.effectParam
                        local fx = (e == 0 and p == 0) and "..." or string.format("%X%02X", e, p)
                        text(fx, x + L.fx, y, col(fxColor(e, p)))
                    end
                end
            end
        end
    end
end

local SCROLL = "     MOD PLAYER BY SIENCE.GITHUB.IO  *  MADE WITH LOVE2D  *  "
    .. "PROTRACKER REPLAY AFTER THE FIRELIGHT MOD TUTORIAL BY BRETT PATERSON  *  "
    .. "PURE LUA SOFTWARE MIXER  *  ALSO RUNS ON LOVEDOS  *  PRESS TAB TO BROWSE FOR MUSIC  *  "
    .. "DROP A FOLDER OR .MOD FILE ON THE WINDOW  *  GREETINGS TO THE AMIGA AND PC DEMOSCENE  *"
local RAINBOW = { C.lred, C.yellow, C.lgreen, C.lcyan, C.lblue, C.lmagenta }
local scrollText, scrollMod = SCROLL, nil

-- Sample names often carry the composer's messages: scroll them after the credits
local function scrollerText(m)
    if m == scrollMod then return scrollText end
    scrollMod, scrollText = m, SCROLL
    if m then
        local names = {}
        for _, smp in ipairs(m.samples) do
            local n = trim(ascii(smp.name))
            if n ~= "" then names[#names + 1] = n end
        end
        if #names > 0 then
            scrollText = SCROLL .. "  SAMPLES: " .. table.concat(names, " / ") .. "  *"
        end
    end
    return scrollText
end

local function drawScroller(app)
    local msg = scrollerText(app.mod)
    local y0 = 372
    local total = #msg * 8
    local off = floor(time * 48) % (total + W)
    local first = max(1, floor((off - W) / 8))
    for i = first, min(#msg, first + W / 8 + 2) do
        local x = W - off + (i - 1) * 8
        if x > -8 and x < W then
            local ch = msg:sub(i, i)
            if ch ~= " " then
                local y = y0 + floor(sin(time * 4 + x * 0.045) * 2.5 + 0.5)
                local c = RAINBOW[floor((x + time * 90) / 24) % #RAINBOW + 1]
                shadow(ch, x, y, c)
            end
        end
    end
end

local KEYS = {
    {"SPC", "Play"}, {"←→", "Track"}, {"TAB", "Files"}, {"R", "Rew"},
    {"I", "Interp"}, {"S", "CRT"}, {"F11", "Full"}, {"ESC", "Quit"},
}

local function drawStatusBar()
    rect(0, 388, W, 12, C.lgray)
    local x = 8
    for _, k in ipairs(KEYS) do
        text(k[1], x, 390, C.red);   x = x + (len(k[1]) + 1) * 8
        text(k[2], x, 390, C.black); x = x + (len(k[2]) + 1) * 8
    end
end

-- ── File browser overlay ─────────────────────────────────────────────────────
local BX, BY, BW, BH = 72, 56, 496, 300
local LIST_Y, LIST_ROWS, ROW_H = BY + 30, 24, 10

function ui.browserRows() return LIST_ROWS end

-- Index of the list entry at canvas position (x, y), or nil.
function ui.browserHit(b, x, y)
    if x < BX + 4 or x > BX + BW - 5 then return nil end
    local r = floor((y - LIST_Y) / ROW_H)
    if r < 0 or r >= LIST_ROWS then return nil end
    local i = b.scroll + r + 1
    if i <= #b.items then return i end
end

local function drawBrowser(b)
    rect(BX, BY, BW, BH, C.black)
    frame(BX, BY, BW, BH, C.lcyan)
    frame(BX + 2, BY + 2, BW - 4, BH - 4, C.cyan)
    rect(BX + 3, BY + 3, BW - 6, 10, C.cyan)
    text(" FILES ", BX + 8, BY + 4, C.black)
    local info = string.format("%d ITEMS", #b.items)
    text(info, BX + BW - 8 - len(info) * 8, BY + 4, C.black)
    text(fit(b.title, 58), BX + 8, BY + 17, C.yellow)
    for r = 0, LIST_ROWS - 1 do
        local i = b.scroll + r + 1
        local it = b.items[i]
        if not it then break end
        local y = LIST_Y + r * ROW_H
        local sel = i == b.sel
        if sel then rect(BX + 4, y - 1, BW - 8, ROW_H, C.lcyan) end
        local name, tag, c
        if it.kind == "up" then name, tag, c = "..", "<UP>", C.lgray
        elseif it.kind == "drive" then name, tag, c = it.name, "<DRIVE>", C.lgreen
        elseif it.kind == "dir" then name, tag, c = it.name, "<DIR>", C.lcyan
        else name, tag, c = "♪ " .. it.name, "", C.white end
        if sel then c = C.black end
        text(fit(name, 50), BX + 10, y, c)
        if tag ~= "" then text(tag, BX + BW - 10 - len(tag) * 8, y, sel and C.black or C.dgray) end
    end
    if #b.items == 0 then text("(no folders or .MOD files)", BX + 10, LIST_Y, C.dgray) end
    local hint = "↑↓ Select  ENTER Open  BKSP Up  TAB Close"
    text(hint, BX + floor((BW - len(hint) * 8) / 2), BY + BH - 14, C.lgray)
end

local function drawMessage(app)
    if not app.message then return end
    local s = fit(app.message, 70)
    local w = len(s) * 8 + 16
    local x, y = floor((W - w) / 2), 300
    rect(x, y, w, 16, C.black)
    frame(x, y, w, 16, C.yellow)
    text(s, x + 8, y + 4, C.yellow)
end

-- ── Draw everything ──────────────────────────────────────────────────────────
function ui.draw(app)
    lg.setCanvas(canvas)
    lg.clear(0, 0, 0, 1)
    drawHeader(app)
    drawInfoBar(app)
    drawScope(8, 56, 200, 84)
    drawSpectrum(216, 56, 264, 84)
    drawVU(app, 488, 56, 144, 84)
    drawPattern(app)
    drawScroller(app)
    drawStatusBar()
    if app.browser.open then drawBrowser(app.browser) end
    drawMessage(app)
    lg.setCanvas()

    lg.clear(0, 0, 0, 1)
    lg.setColor(1, 1, 1, 1)
    lg.draw(canvas, ox, oy, 0, scale, scale)
    if app.scanlines and scale >= 2 then
        lg.setColor(0, 0, 0, 0.35)
        local h = floor(scale / 2)
        for y = 0, H - 1 do
            lg.rectangle("fill", ox, oy + y * scale + scale - h, W * scale, h)
        end
    end
end

return ui
