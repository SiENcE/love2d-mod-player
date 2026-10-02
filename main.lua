-- Complete MOD Player Implementation for LÖVE and LÖVE-DOS
--
-- One ProTracker player core (FMODDOC.TXT) drives one of two audio backends:
--   * Mixer  (USE_SOFTWARE_LOOP = true)  – LÖVE 11+.  All channels are mixed in
--     Lua and streamed through a single QueueableSource: sample-exact tick
--     timing, exact sample loops (even tiny chip loops), 9xx offsets, retrigs.
--   * Source (USE_SOFTWARE_LOOP = false) – LoveDOS compatibility layer.  LoveDOS
--     can only load sounds from .wav files and its Sources have no seek(), so
--     every sample (and each loop / 9xx offset part of it) is written to the
--     save directory and played as its own Source.

-- ───────────────────────────────────────────────────────────────
--  Configuration
-- ───────────────────────────────────────────────────────────────

-- true  = software mixer (needs love.audio.newQueueableSource, LÖVE 11+)
-- false = LoveDOS Source backend (also used automatically when the mixer API
--         is missing, so LoveDOS works even if this is set to true)
local USE_SOFTWARE_LOOP = false

-- Song to start with (or pass a file: love . MUSIC/foo.mod).  MUSIC/ is not in
-- git (no redistribution rights); without the file the demo song plays.
local DEFAULT_MOD = "MUSIC/demo.mod"
local DEMO_MOD    = "demo.mod"  -- our own song (MIT), shipped with the player

local MIX_RATE        = 44100  -- mixer output rate (Hz)
local MIX_BUFFER      = 1024   -- frames per queued buffer (~23 ms)
local MIX_BUFFERS     = 4      -- buffers kept queued (latency ~ MIX_BUFFERS * MIX_BUFFER)
local MIX_INTERPOLATE = false  -- true = linear interpolation (smoother); false = raw like Paula

-- NTSC Amiga clock (FMODDOC §3.5): period 428 (C-2) plays at 8363 Hz
local AMIGA_CLOCK = 7159090.5 / 2

-- LoveDOS has no love.window (and never reads conf.lua).  It keeps the plain
-- text screen; desktop LÖVE gets the retro UI in ui.lua.
local IS_LOVEDOS = love.window == nil

local interpolate = MIX_INTERPOLATE  -- runtime copy, toggled with I in the UI

if USE_SOFTWARE_LOOP and not (love.audio.newQueueableSource and love.sound and love.sound.newSoundData) then
    print("Info: no QueueableSource support – using the LoveDOS Source backend.")
    USE_SOFTWARE_LOOP = false
end

-- Period to pitch conversion table
local PERIOD_TABLE = {
    {1712, 1616, 1524, 1440, 1356, 1280, 1208, 1140, 1076, 1016, 960 , 906,
     856 , 808 , 762 , 720 , 678 , 640 , 604 , 570 , 538 , 508 , 480 , 453,
     428 , 404 , 381 , 360 , 339 , 320 , 302 , 285 , 269 , 254 , 240 , 226,
     214 , 202 , 190 , 180 , 170 , 160 , 151 , 143 , 135 , 127 , 120 , 113,
     107 , 101 , 95  , 90  , 85  , 80  , 75  , 71  , 67  , 63  , 60  , 56},

    {1700, 1604, 1514, 1430, 1348, 1274, 1202, 1134, 1070, 1010, 954 , 900,
     850 , 802 , 757 , 715 , 674 , 637 , 601 , 567 , 535 , 505 , 477 , 450,
     425 , 401 , 379 , 357 , 337 , 318 , 300 , 284 , 268 , 253 , 239 , 225,
     213 , 201 , 189 , 179 , 169 , 159 , 150 , 142 , 134 , 126 , 119 , 113,
     106 , 100 , 94  , 89  , 84  , 79  , 75  , 71  , 67  , 63  , 59  , 56},

    {1688, 1592, 1504, 1418, 1340, 1264, 1194, 1126, 1064, 1004, 948 , 894,
     844 , 796 , 752 , 709 , 670 , 632 , 597 , 563 , 532 , 502 , 474 , 447,
     422 , 398 , 376 , 355 , 335 , 316 , 298 , 282 , 266 , 251 , 237 , 224,
     211 , 199 , 188 , 177 , 167 , 158 , 149 , 141 , 133 , 125 , 118 , 112,
     105 , 99  , 94  , 88  , 83  , 79  , 74  , 70  , 66  , 62  , 59  , 56},

    {1676, 1582, 1492, 1408, 1330, 1256, 1184, 1118, 1056, 996 , 940 , 888,
     838 , 791 , 746 , 704 , 665 , 628 , 592 , 559 , 528 , 498 , 470 , 444,
     419 , 395 , 373 , 352 , 332 , 314 , 296 , 280 , 264 , 249 , 235 , 222,
     209 , 198 , 187 , 176 , 166 , 157 , 148 , 140 , 132 , 125 , 118 , 111,
     104 , 99  , 93  , 88  , 83  , 78  , 74  , 70  , 66  , 62  , 59  , 55},

    {1664, 1570, 1482, 1398, 1320, 1246, 1176, 1110, 1048, 990 , 934 , 882,
     832 , 785 , 741 , 699 , 660 , 623 , 588 , 555 , 524 , 495 , 467 , 441,
     416 , 392 , 370 , 350 , 330 , 312 , 294 , 278 , 262 , 247 , 233 , 220,
     208 , 196 , 185 , 175 , 165 , 156 , 147 , 139 , 131 , 124 , 117 , 110,
     104 , 98  , 92  , 87  , 82  , 78  , 73  , 69  , 65  , 62  , 58  , 55},

    {1652, 1558, 1472, 1388, 1310, 1238, 1168, 1102, 1040, 982 , 926 , 874,
     826 , 779 , 736 , 694 , 655 , 619 , 584 , 551 , 520 , 491 , 463 , 437,
     413 , 390 , 368 , 347 , 328 , 309 , 292 , 276 , 260 , 245 , 232 , 219,
     206 , 195 , 184 , 174 , 164 , 155 , 146 , 138 , 130 , 123 , 116 , 109,
     103 , 97  , 92  , 87  , 82  , 77  , 73  , 69  , 65  , 61  , 58  , 54},

    {1640, 1548, 1460, 1378, 1302, 1228, 1160, 1094, 1032, 974 , 920 , 868,
     820 , 774 , 730 , 689 , 651 , 614 , 580 , 547 , 516 , 487 , 460 , 434,
     410 , 387 , 365 , 345 , 325 , 307 , 290 , 274 , 258 , 244 , 230 , 217,
     205 , 193 , 183 , 172 , 163 , 154 , 145 , 137 , 129 , 122 , 115 , 109,
     102 , 96  , 91  , 86  , 81  , 77  , 72  , 68  , 64  , 61  , 57  , 54},

    {1628, 1536, 1450, 1368, 1292, 1220, 1150, 1086, 1026, 968 , 914 , 862,
     814 , 768 , 725 , 684 , 646 , 610 , 575 , 543 , 513 , 484 , 457 , 431,
     407 , 384 , 363 , 342 , 323 , 305 , 288 , 272 , 256 , 242 , 228 , 216,
     204 , 192 , 181 , 171 , 161 , 152 , 144 , 136 , 128 , 121 , 114 , 108,
     102 , 96  , 90  , 85  , 80  , 76  , 72  , 68  , 64  , 60  , 57  , 54},

    {1814, 1712, 1616, 1524, 1440, 1356, 1280, 1208, 1140, 1076, 1016, 960,
     907 , 856 , 808 , 762 , 720 , 678 , 640 , 604 , 570 , 538 , 508 , 480,
     453 , 428 , 404 , 381 , 360 , 339 , 320 , 302 , 285 , 269 , 254 , 240,
     226 , 214 , 202 , 190 , 180 , 170 , 160 , 151 , 143 , 135 , 127 , 120,
     113 , 107 , 101 , 95  , 90  , 85  , 80  , 75  , 71  , 67  , 63  , 60},

    {1800, 1700, 1604, 1514, 1430, 1350, 1272, 1202, 1134, 1070, 1010, 954,
     900 , 850 , 802 , 757 , 715 , 675 , 636 , 601 , 567 , 535 , 505 , 477,
     450 , 425 , 401 , 379 , 357 , 337 , 318 , 300 , 284 , 268 , 253 , 238,
     225 , 212 , 200 , 189 , 179 , 169 , 159 , 150 , 142 , 134 , 126 , 119,
     112 , 106 , 100 , 94  , 89  , 84  , 79  , 75  , 71  , 67  , 63  , 60},

    -- Tuning -6
    {1788, 1688, 1592, 1504, 1418, 1340, 1264, 1194, 1126, 1064, 1004, 948,
     894 , 844 , 796 , 752 , 709 , 670 , 632 , 597 , 563 , 532 , 502 , 474,
     447 , 422 , 398 , 376 , 355 , 335 , 316 , 298 , 282 , 266 , 251 , 237,
     223 , 211 , 199 , 188 , 177 , 167 , 158 , 149 , 141 , 133 , 125 , 118,
     112 , 106 , 100 , 94  , 89  , 84  , 79  , 75  , 71  , 67  , 63  , 59},

    -- Tuning -5
    {1774, 1676, 1582, 1492, 1408, 1330, 1256, 1184, 1118, 1056, 996 , 940,
     887 , 838 , 791 , 746 , 704 , 665 , 628 , 592 , 559 , 528 , 498 , 470,
     444 , 419 , 395 , 373 , 352 , 332 , 314 , 296 , 280 , 264 , 249 , 235,
     222 , 209 , 198 , 187 , 176 , 166 , 157 , 148 , 140 , 132 , 125 , 118,
     111 , 105 , 99  , 94  , 88  , 83  , 79  , 74  , 70  , 66  , 63  , 59},

    -- Tuning -4
    {1762, 1664, 1570, 1482, 1398, 1320, 1246, 1176, 1110, 1048, 988 , 934,
     881 , 832 , 785 , 741 , 699 , 660 , 623 , 588 , 555 , 524 , 494 , 467,
     441 , 416 , 392 , 370 , 350 , 330 , 312 , 294 , 278 , 262 , 247 , 233,
     220 , 208 , 196 , 185 , 175 , 165 , 156 , 147 , 139 , 131 , 123 , 117,
     110 , 104 , 98  , 93  , 88  , 83  , 78  , 74  , 70  , 66  , 62  , 59},

    -- Tuning -3
    {1750, 1652, 1558, 1472, 1388, 1310, 1238, 1168, 1102, 1040, 982 , 926,
     875 , 826 , 779 , 736 , 694 , 655 , 619 , 584 , 551 , 520 , 491 , 463,
     437 , 413 , 390 , 368 , 347 , 328 , 309 , 292 , 276 , 260 , 245 , 232,
     219 , 206 , 195 , 184 , 174 , 164 , 155 , 146 , 138 , 130 , 123 , 116,
     110 , 103 , 98  , 92  , 87  , 82  , 78  , 73  , 69  , 65  , 62  , 58},

    -- Tuning -2
    {1736, 1640, 1548, 1460, 1378, 1302, 1228, 1160, 1094, 1032, 974 , 920,
     868 , 820 , 774 , 730 , 689 , 651 , 614 , 580 , 547 , 516 , 487 , 460,
     434 , 410 , 387 , 365 , 345 , 325 , 307 , 290 , 274 , 258 , 244 , 230,
     217 , 205 , 193 , 183 , 172 , 163 , 154 , 145 , 137 , 129 , 122 , 115,
     109 , 103 , 97  , 92  , 86  , 82  , 77  , 73  , 69  , 65  , 61  , 58},

    -- Tuning -1
    {1724, 1628, 1536, 1450, 1368, 1292, 1220, 1150, 1086, 1026, 968 , 914,
     862 , 814 , 768 , 725 , 684 , 646 , 610 , 575 , 543 , 513 , 484 , 457,
     431 , 407 , 384 , 363 , 342 , 323 , 305 , 288 , 272 , 256 , 242 , 228,
     216 , 203 , 192 , 181 , 171 , 161 , 152 , 144 , 136 , 128 , 121 , 114,
     108 , 102 , 96  , 91  , 86  , 81  , 76  , 72  , 68  , 64  , 61  , 57}
}

-- Global variables
local mod
local currentPattern = 0
local currentPatternIndex = 1
local currentRow = 1
local currentTick = 0
local ticksPerRow = 6  -- Default speed (ticks per row)
local bpm = 125        -- Default BPM (125 BPM = 50 ticks/sec)
local songStarted = false -- false until the first row has been played
local songEnded   = false -- set by F00 (ProTracker: stop the song)
local songTime    = 0     -- seconds of song played (sum of tick lengths)
local channels = {}
local play = false
local backend          -- Mixer or Source (see bottom of file), chosen in love.load

-- Protracker sine table (32 entries, one half-wave 0..255)
local SINE_TABLE = {
    0,  24,  49,  74,  97, 120, 141, 161,
  180, 197, 212, 224, 235, 244, 250, 253,
  255, 253, 250, 244, 235, 224, 212, 197,
  180, 161, 141, 120,  97,  74,  49,  24
}

-- Pattern-navigation state (set during updateRow, consumed at row boundary)
local jumpToOrder  = nil   -- Bxy: jump to this order index (0-based)
local breakToRow   = nil   -- Dxy: break to this row in next order (0-based)
local loopToRow    = nil   -- E6x: jump back to this row in the SAME pattern (1-based)
local patDelay     = 0     -- EEx: how many extra "row holds" remain
local loopRow      = {}    -- E6x per channel: stored loop-start row (1-based)
local loopCount    = {}    -- E6x per channel: remaining loop iterations

-- Amiga default channel panning.
-- Pattern repeats every 4: Left, Right, Right, Left (hard-panned as on original hardware).
-- Value range: -1.0 (full left) to +1.0 (full right).
local AMIGA_PAN = { -1.0, 1.0, 1.0, -1.0 }

local EMPTY_NOTE = { sample = 0, period = 0, effect = 0, effectParam = 0 }

-- Nibble helpers.  Plain arithmetic: an emulated bit32 costs a 32-step loop per
-- call, which adds up on LoveDOS where these run every row and tick.
local function hiNibble(b) return math.floor(b / 16) end
local function loNibble(b) return b % 16 end

-- Finetune (-8..7) → row in PERIOD_TABLE (0..7 → 1..8, -8..-1 → 9..16)
local function ftIndex(finetune)
    return (finetune >= 0) and (finetune + 1) or (finetune + 17)
end

-- Index (1-60) of the note in PERIOD_TABLE[ftIdx] closest to period
local function nearestNote(ftIdx, period)
    local row = PERIOD_TABLE[ftIdx]
    local best, bestDiff = 1, math.huge
    for i = 1, 60 do
        local d = math.abs(row[i] - period)
        if d < bestDiff then bestDiff = d; best = i end
    end
    return best
end

local function clampPeriod(period)
    return math.max(54, math.min(1712, math.floor(period)))
end

-- MOD File Loader and Parser for LÖVE-DOS
local function readString(data, offset, length)
    return string.sub(data, offset, offset + length - 1)
end

local function readUint16BigEndian(data, offset)
    local byte1, byte2 = string.byte(data, offset, offset + 1)
    return byte1 * 256 + byte2
end

local function readUint8(data, offset)
    return string.byte(data, offset)
end

local function parseSample(fileData, offset)
    local sample = {}
    sample.name = readString(fileData, offset, 22)  -- Read sample name (22 bytes)
    sample.length = readUint16BigEndian(fileData, offset + 22) * 2 -- Read sample length (2 bytes) and convert to bytes
    local ft = loNibble(readUint8(fileData, offset + 24)) -- lower 4 bits only
    if ft > 7 then ft = ft - 16 end -- signed: 8..15 -> -8..-1
    sample.finetune = ft -- Finetune value
    sample.volume = math.min(readUint8(fileData, offset + 25), 64) -- Volume, clamped to 0-64
    sample.loopStart = readUint16BigEndian(fileData, offset + 26) * 2 -- Repeat point
    sample.loopLength = readUint16BigEndian(fileData, offset + 28) * 2 -- Repeat length
    return sample
end

local function parsePatterns(data, offset, numPatterns, numChannels)
    local patterns = {}
    for p = 0, numPatterns - 1 do
        local pattern = {}
        for row = 1, 64 do
            local rowData = {}
            for channel = 1, numChannels do
                local byte1, byte2, byte3, byte4 = string.byte(data, offset, offset + 3)
                if byte4 then
                    -- FMODDOC §2.6: aaaaBBBB CCCCCCCC DDDDeeee FFFFFFFF
                    rowData[channel] = {
                        sample      = (byte1 - byte1 % 16) + hiNibble(byte3),
                        period      = (byte1 % 16) * 256 + byte2,
                        effect      = byte3 % 16,
                        effectParam = byte4,
                    }
                else
                    rowData[channel] = EMPTY_NOTE  -- truncated file
                end
                offset = offset + 4
            end
            pattern[row] = rowData
        end
        patterns[p] = pattern
    end
    return patterns
end

--[[
For a typical "M.K." MOD file, the structure is as follows:
1. File Header: 1084 bytes
	* Song name: 20 bytes
	* 31 sample headers: 31 * 30 = 930 bytes
	* Number of song positions: 1 byte
	* Used to restart song: 1 byte
	* Song positions: 128 bytes
	* File format tag ("M.K."): 4 bytes

2. Pattern Data: Variable length
	* Each pattern is 1024 bytes (64 rows * 4 channels * 4 bytes per note)
	* The number of patterns can vary

3. Sample Data: Starts after the pattern data
	To calculate the offset where samples start:
	* Start with the header size: 1084 bytes
	* Add the size of all patterns: (number of patterns * 1024 bytes)
]]--
local function parseMOD(fileData)
    if #fileData < 600 then error("Not a MOD file (too short)") end

    local mod = {}

    -- Parse header
    mod.name = readString(fileData, 1, 20)

    -- ── Format detection ──────────────────────────────────────────────────────
    -- Modern 31-sample MODs carry a 4-byte tag at byte 1081.
    -- Old 15-sample MODs (Ultimate Soundtracker / Soundtracker M15) have no tag.
    --
    -- Layout comparison (all offsets 1-based, Lua style):
    --   31-sample: 20 + 31*30 + 1 + 1 + 128 + 4  = 1084 → patterns at 1085
    --   15-sample: 20 + 15*30 + 1 + 1 + 128       =  600 → patterns at  601
    -- ─────────────────────────────────────────────────────────────────────────
    local magicBytes  = readString(fileData, 1081, 4)
    local numChannels = 4
    local numSamples  = 31
    local songLenOff  = 951   -- offset of "song length" byte (31-sample format)
    local patternBase = 1085  -- offset where pattern data begins (31-sample format)

    if magicBytes == "M.K." or magicBytes == "M!K!" or magicBytes == "M&K!"
        or magicBytes == "N.T." or magicBytes == "FLT4" then
        numChannels = 4
    elseif magicBytes == "FLT8" or magicBytes == "CD81" or magicBytes == "OKTA" or magicBytes == "OCTA" then
        numChannels = 8  -- FLT8's split pattern layout is handled below
    elseif string.sub(magicBytes, 2, 4) == "CHN" and tonumber(string.sub(magicBytes, 1, 1)) then
        -- "2CHN" … "9CHN"
        numChannels = tonumber(string.sub(magicBytes, 1, 1))
    elseif (string.sub(magicBytes, 3, 4) == "CH" or string.sub(magicBytes, 3, 4) == "CN")
        and tonumber(string.sub(magicBytes, 1, 2)) then
        -- e.g. "10CH", "12CH" … "32CH": the channel count is the first 2 chars.
        numChannels = tonumber(string.sub(magicBytes, 1, 2))
    elseif string.sub(magicBytes, 1, 3) == "TDZ" and tonumber(string.sub(magicBytes, 4, 4)) then
        numChannels = tonumber(string.sub(magicBytes, 4, 4))
    else
        -- ── Old 15-sample "M15" format ──────────────────────────────────────
        -- No tag, only 15 sample slots, header is 600 bytes.
        print("Info: No M.K. tag found – assuming old 15-sample (M15) format.")
        numSamples  = 15
        songLenOff  = 471   -- 20 + 15*30 + 1   (1-based)
        patternBase = 601   -- 20 + 15*30 + 1 + 1 + 128 + 1  (1-based)
        numChannels = 4
    end
    mod.numChannels = numChannels
    mod.format      = (numSamples == 15) and "M15" or magicBytes

    -- Parse sample headers (15 or 31)
    mod.samples = {}
    for i = 1, numSamples do
        mod.samples[i] = parseSample(fileData, 21 + (i - 1) * 30)
    end

    -- Read song length and restart position
    mod.songLength       = readUint8(fileData, songLenOff)
    mod.restartPosition  = readUint8(fileData, songLenOff + 1)

    -- Clamp song length to valid range
    if mod.songLength == 0 or mod.songLength > 128 then
        mod.songLength = 128
    end

    -- Restart position: 0-based order index the song loops back to at the end.
    -- Values >= songLength (commonly 127 / 0x7F) mean "no restart" → loop to 0.
    if mod.restartPosition >= mod.songLength then
        mod.restartPosition = 0
    end

    -- Read pattern order table (128 bytes follow song-length byte)
    mod.patternTable = {}
    local highestPattern = 0
    for i = 1, 128 do
        mod.patternTable[i] = readUint8(fileData, songLenOff + 1 + i)
        highestPattern = math.max(highestPattern, mod.patternTable[i])
    end

    -- Parse patterns
    local patternBytes
    if magicBytes == "FLT8" then
        -- Startrekker 8-channel: each pattern is stored as two 4-channel
        -- patterns (channels 1-4, then 5-8), and the order list counts those
        -- 4-channel halves, so its entries are always even: halve them.
        highestPattern = 0
        for i = 1, 128 do
            mod.patternTable[i] = math.floor(mod.patternTable[i] / 2)
            highestPattern = math.max(highestPattern, mod.patternTable[i])
        end
        local halves = parsePatterns(fileData, patternBase, (highestPattern + 1) * 2, 4)
        mod.patterns = {}
        for p = 0, highestPattern do
            local pattern, left, right = {}, halves[p * 2], halves[p * 2 + 1]
            for row = 1, 64 do
                local rowData = {}
                for c = 1, 4 do
                    rowData[c]     = left[row][c]
                    rowData[c + 4] = right[row][c]
                end
                pattern[row] = rowData
            end
            mod.patterns[p] = pattern
        end
        patternBytes = (highestPattern + 1) * 2 * 64 * 4 * 4
    else
        mod.patterns = parsePatterns(fileData, patternBase, highestPattern + 1, numChannels)
        patternBytes = (highestPattern + 1) * 64 * numChannels * 4
    end

    -- Parse sample data
    local sampleDataOffset = patternBase + patternBytes
    for i, sample in ipairs(mod.samples) do
        sample.baseFinetune = sample.finetune  -- E5x changes finetune; restored on restart
        sample.data = readString(fileData, sampleDataOffset, sample.length)
        sampleDataOffset = sampleDataOffset + sample.length
        sample.length = #sample.data  -- a truncated file holds less than the header claims

        -- Loop points.  A repeat length of 1 word (2 bytes) means "no loop".
        -- Old Soundtracker modules store the repeat point in bytes rather than
        -- words; if the loop runs past the end, try that before clamping it.
        local ls, ll = sample.loopStart, sample.loopLength
        if ll > 2 and ls + ll > sample.length then
            if ls / 2 + ll <= sample.length then
                ls = ls / 2
            else
                ll = sample.length - ls
            end
        end
        sample.hasLoop   = ll > 2
        sample.loopStart = ls
        sample.loopEnd   = ls + ll
    end

    print(string.format("Loaded: '%s'  samples=%d  channels=%d  orders=%d  patterns=%d",
        mod.name, numSamples, numChannels, mod.songLength, highestPattern + 1))

    return mod
end

-- Play the MOD data
-- Initialize audio channels
local function initializeChannels()
    for i = 1, mod.numChannels do
        local pan = AMIGA_PAN[((i - 1) % 4) + 1]
        channels[i] = {
            period      = 0,        -- current base period (Amiga value)
            volume      = 0,        -- current base volume (0-64)
            pan         = pan,
            lastSample  = 0,        -- last instrument number seen (1-31)
            sampleNum   = 0,        -- sample currently playing (for E9x retrig)
            ftIdx       = 1,        -- finetune row index in PERIOD_TABLE (1-16)
            -- Portamento (effect 3,5; 1xy/2xy have no memory)
            portaTarget = 0,        -- target period for effect 3
            portaSpeed  = 0,        -- speed for effect 3
            glissando   = false,    -- E3x: snap porta to semitones
            -- Vibrato (effects 4,6)
            vibratoSpeed    = 0,
            vibratoDepth    = 0,
            vibratoPos      = 0,    -- 0-31 position in sine table
            vibratoNeg      = 0,    -- 0=add delta, 1=subtract delta
            vibratoWaveform = 0,    -- 0=sine,1=ramp,2=square,3=random
            -- Tremolo (effect 7)
            tremoloSpeed    = 0,
            tremoloDepth    = 0,
            tremoloPos      = 0,
            tremoloNeg      = 0,
            tremoloWaveform = 0,
            -- Volume slide (effects A,5,6)
            volSlideUp   = 0,
            volSlideDown = 0,
            -- Sample offset memory (effect 9xx; 9x0 reuses last offset)
            sampleOffset = 0,
            -- Delay note (EDx)
            delayNote = nil,
            delayTick = 0,
            -- Current row's note (used by doEffects on in-between ticks)
            currentNote = nil,
            -- ── Output "registers", read by the backend after every tick ──
            outPeriod  = 0,     -- period to play this tick (incl. vibrato/arpeggio)
            outVolume  = 0,     -- volume to play this tick (incl. tremolo)
            trigSample = nil,   -- set → (re)start this sample on the next commit
            trigOffset = 0,     -- start offset in bytes for trigSample
        }
        loopRow[i]   = 1   -- default loop start = top of pattern (1-based)
        loopCount[i] = 0
    end
end

-- ───────────────────────────────────────────────────────────────
--  Low-level channel helpers
--  The player core never touches audio objects: it only updates the
--  channel state and output registers, and the backend applies them.
-- ───────────────────────────────────────────────────────────────

-- Clamp and apply a volume (0-64) to a channel and store it as its base volume.
local function setChannelVolume(ch, vol)
    vol = math.max(0, math.min(64, math.floor(vol)))
    channels[ch].volume = vol
    channels[ch].outVolume = vol
end

-- Store a new base period for a channel and play it.
local function setChannelPeriod(ch, period)
    period = clampPeriod(period)
    channels[ch].period = period
    channels[ch].outPeriod = period
end

-- Apply a transient pitch offset (vibrato/arpeggio) without storing it.
local function setPitchDirect(ch, period)
    channels[ch].outPeriod = clampPeriod(period)
end

-- Return waveform amplitude (0-255) for position pos (0-31) of the given waveform.
-- waveform: 0=sine, 1=ramp-down, 2=square, 3+=random  (bit 2 = don't-retrig flag)
local function getWaveValue(waveform, pos)
    local shape = waveform % 4
    if shape == 0 then
        return SINE_TABLE[pos + 1]
    elseif shape == 1 then
        return 255 - pos * 8          -- ramp: 255 → 7
    elseif shape == 2 then
        return 255                    -- square: constant amplitude, neg flag alternates
    else
        return math.random(0, 255)    -- random
    end
end

-- Advance a vibrato/tremolo oscillator and return the signed delta.
-- Returns (delta, newPos, newNeg).
local function oscillatorStep(waveform, pos, neg, speed, depth, divisor)
    local amp   = getWaveValue(waveform, pos)
    local delta = math.floor(depth * amp / divisor)
    if neg == 1 then delta = -delta end
    -- Advance position
    pos = pos + speed
    if pos > 31 then
        pos = pos - 32
        neg = 1 - neg
    end
    return delta, pos, neg
end

-- Perform a volume slide using stored up/down amounts.
local function doVolumeSlide(ch)
    local up   = channels[ch].volSlideUp
    local down = channels[ch].volSlideDown
    if up > 0 and down == 0 then
        setChannelVolume(ch, channels[ch].volume + up)
    elseif down > 0 and up == 0 then
        setChannelVolume(ch, channels[ch].volume - down)
    -- if both non-zero: do nothing (per spec)
    end
end

-- Perform portamento-toward-target for a channel.
local function doPortamento(ch)
    local c   = channels[ch]
    local cur = c.period
    local tgt = c.portaTarget
    local spd = c.portaSpeed
    if tgt == 0 or cur == tgt then return end
    if cur < tgt then
        cur = math.min(cur + spd, tgt)
    else
        cur = math.max(cur - spd, tgt)
    end
    setChannelPeriod(ch, cur)
    -- Glissando: the slide itself stays smooth, only the audible pitch snaps
    -- to the nearest semitone.  (Snapping the stored period would make slow
    -- slides round back to the start note every tick and never arrive.)
    if c.glissando then
        c.outPeriod = PERIOD_TABLE[c.ftIdx][nearestNote(c.ftIdx, cur)]
    end
end

-- ───────────────────────────────────────────────────────────────
--  triggerSample: start/restart sample playback for a channel.
--  Called from playNote (tick 0) and doEffects (EDx delay).
--  finetune overrides the sample's finetune (E5x on the same row).
-- ───────────────────────────────────────────────────────────────
local function triggerSample(channel, note, seekBytes, finetune)
    local ch = channels[channel]

    -- Determine which sample number to use
    local sampleNum = (note.sample > 0) and note.sample or ch.lastSample
    local sample = mod.samples[sampleNum]
    if not sample then return end

    -- Ask the backend to (re)start the sample after this tick.  An empty
    -- sample still triggers: it silences the channel, as in ProTracker.  An
    -- offset past the end is resolved by the backend (loop part or silence).
    ch.sampleNum  = sampleNum
    ch.trigSample = sampleNum
    ch.trigOffset = seekBytes or 0

    -- Set pitch using the finetune-adjusted period (FMODDOC §3.4)
    local ftIdx = ftIndex(finetune or sample.finetune or 0)
    ch.ftIdx = ftIdx
    local tunedPeriod = PERIOD_TABLE[ftIdx][nearestNote(1, note.period)]
    ch.period    = tunedPeriod
    ch.outPeriod = tunedPeriod
    ch.outVolume = ch.volume

    -- Reset vibrato/tremolo phase if waveform < 4 (retrig enabled)
    if ch.vibratoWaveform < 4 then
        ch.vibratoPos = 0; ch.vibratoNeg = 0
    end
    if ch.tremoloWaveform < 4 then
        ch.tremoloPos = 0; ch.tremoloNeg = 0
    end
end

-- ───────────────────────────────────────────────────────────────
--  playNote  (tick 0 processing for one channel)
-- ───────────────────────────────────────────────────────────────
local function playNote(channel, note)
    local ch      = channels[channel]
    local effect  = note.effect
    local param   = note.effectParam
    local ex      = hiNibble(param)   -- high nibble
    local ey      = loNibble(param)   -- low  nibble

    -- Remember this row's note so doEffects can continue it on in-between ticks
    ch.currentNote = note
    ch.delayNote   = nil

    -- Clear any residual transient pitch/volume left by the previous row's
    -- vibrato / tremolo / arpeggio.  ProTracker reloads the base period and
    -- volume at the start of every row (tick 0); the oscillating effects then
    -- re-apply their offset on ticks > 0.  Without this, a vibrato row followed
    -- by a plain row stays detuned, and tremolo sticks at the wrong volume.
    ch.outPeriod = ch.period
    ch.outVolume = ch.volume

    -- Porta-to-Note flag: don't restart the sample (effects 3 and 5)
    local isPorta = (effect == 0x3 or effect == 0x5)
    -- Delay-Note flag: don't play now (effect EDx; ED0 plays immediately)
    local isDelay = (effect == 0xE and ex == 0xD and ey > 0)

    -- ── Section 4.1: volume reset only when instrument number is present ──
    local instrument = note.sample > 0 and mod.samples[note.sample]
    if instrument then
        ch.volume    = instrument.volume
        ch.outVolume = instrument.volume
        ch.lastSample = note.sample
    end

    -- ── Porta target / speed update (effect 3) ──
    if isPorta then
        if note.period > 0 then
            -- Slide to the finetuned period, the same one a normal trigger plays
            local s = mod.samples[ch.lastSample]
            ch.portaTarget = PERIOD_TABLE[ftIndex(s and s.finetune or 0)][nearestNote(1, note.period)]
        end
        if effect == 0x3 and param ~= 0 then ch.portaSpeed = param end
        -- Effect 5 param = vol-slide amounts (handled below)
    end

    -- ── Trigger sample / set period ──
    if note.period > 0 and not isPorta and not isDelay then
        local seekBytes = 0
        if effect == 0x9 then
            -- 9xx offset is in 256-byte units; 9x0 reuses the last offset.
            if param ~= 0 then ch.sampleOffset = param * 0x100 end
            seekBytes = ch.sampleOffset
        end
        local finetune
        if effect == 0xE and ex == 0x5 then
            -- E5x: Set Finetune – applies to this note already (§5.21)
            finetune = (ey > 7) and (ey - 16) or ey
        end
        triggerSample(channel, note, seekBytes, finetune)
    elseif note.period > 0 and isDelay then
        -- Store for later playback at tick EDy
        ch.delayNote = note
        ch.delayTick = ey
    end

    -- ───────────────────────────────────────────────────────────
    --  Tick-0 effects
    -- ───────────────────────────────────────────────────────────
    if effect == 0x0 then
        -- 0xy Arpeggio: executed on ticks > 0 straight from the note's param

    elseif effect == 0x1 or effect == 0x2 then
        -- 1xy / 2xy Porta Up/Down: slide on ticks > 0, no effect memory

    elseif effect == 0x4 then
        -- 4xy Vibrato: update speed/depth if non-zero
        if ex ~= 0 then ch.vibratoSpeed = ex end
        if ey ~= 0 then ch.vibratoDepth = ey end

    elseif effect == 0x5 then
        -- 5xy Porta+VolSlide: param is vol-slide amounts
        ch.volSlideUp = ex; ch.volSlideDown = ey

    elseif effect == 0x6 then
        -- 6xy Vibrato+VolSlide: param is vol-slide amounts
        ch.volSlideUp = ex; ch.volSlideDown = ey

    elseif effect == 0x7 then
        -- 7xy Tremolo: update speed/depth if non-zero
        if ex ~= 0 then ch.tremoloSpeed = ex end
        if ey ~= 0 then ch.tremoloDepth = ey end

    elseif effect == 0x8 then
        -- 8xy Pan: spec §5.9 – 00=left, 40=centre, 80=right, A4=surround
        if param == 0xA4 then
            ch.pan = 0  -- surround needs a phase-inverted twin voice: centre it
        else
            -- Range 0..128 maps to -1..+1; values above 128 clamp to +1.
            ch.pan = math.max(-1.0, math.min(1.0, (param / 64.0) - 1.0))
        end

    elseif effect == 0x9 then
        -- 9xy Sample Offset: already applied in triggerSample above

    elseif effect == 0xA then
        -- Axy Volume Slide: store params (slide on ticks > 0)
        ch.volSlideUp = ex; ch.volSlideDown = ey

    elseif effect == 0xB then
        -- Bxy Jump To Pattern (order)
        jumpToOrder = param

    elseif effect == 0xC then
        -- Cxy Set Volume
        setChannelVolume(channel, param)

    elseif effect == 0xD then
        -- Dxy Pattern Break (decimal: x*10+y rows into next pattern)
        local row = ex * 10 + ey
        if row > 63 then row = 0 end
        breakToRow = row

    elseif effect == 0xF then
        -- Fxy Set Speed / BPM; F00 stops the song (ProTracker)
        if param == 0 then
            songEnded = true
        elseif param <= 31 then
            ticksPerRow = param
        else
            bpm = param
        end

    elseif effect == 0xE then
        -- Extended effects (Exy)
        local sub = ex    -- sub-command  (high nibble)
        local val = ey    -- sub-value    (low  nibble)

        if sub == 0x0 then
            -- E0x: Set Filter – Amiga hardware, ignore on PC

        elseif sub == 0x1 then
            -- E1x: Fine Porta Up (subtract x from period on tick 0)
            setChannelPeriod(channel, ch.period - val)

        elseif sub == 0x2 then
            -- E2x: Fine Porta Down (add x to period on tick 0)
            setChannelPeriod(channel, ch.period + val)

        elseif sub == 0x3 then
            -- E3x: Glissando Control
            ch.glissando = (val ~= 0)

        elseif sub == 0x4 then
            -- E4x: Set Vibrato Waveform
            ch.vibratoWaveform = val

        elseif sub == 0x5 then
            -- E5x: Set Finetune for the instrument (§5.21); the current note
            -- already used it in triggerSample above.
            local ft = val; if ft > 7 then ft = ft - 16 end
            if instrument then
                instrument.finetune = ft
            end

        elseif sub == 0x6 then
            -- E6x: Pattern Loop (per channel).  E60 marks the loop start row;
            -- E6x (x>0) jumps back to it x times before continuing.  The jump
            -- target is consumed at the row boundary in advanceRow (loopToRow),
            -- staying within the SAME pattern – no order advance.
            if val == 0 then
                loopRow[channel] = currentRow     -- mark loop start
            else
                if loopCount[channel] == 0 then
                    loopCount[channel] = val      -- begin: set iteration count
                else
                    loopCount[channel] = loopCount[channel] - 1
                end
                if loopCount[channel] > 0 then
                    loopToRow = loopRow[channel] or 1
                end
            end

        elseif sub == 0x7 then
            -- E7x: Set Tremolo Waveform
            ch.tremoloWaveform = val

        elseif sub == 0x8 then
            -- E8x: 16-position pan (0=left … Fh=right → -1..+1)
            local pan = (val / 7.5) - 1.0
            pan = math.max(-1.0, math.min(1.0, pan))
            ch.pan = pan

        elseif sub == 0xA then
            -- EAx: Fine Volume Slide Up (tick 0 only)
            setChannelVolume(channel, ch.volume + val)

        elseif sub == 0xB then
            -- EBx: Fine Volume Slide Down (tick 0 only)
            setChannelVolume(channel, ch.volume - val)

        elseif sub == 0xC then
            -- ECx: Cut Note – EC0 cuts right away, others in doEffects
            if val == 0 then setChannelVolume(channel, 0) end

        elseif sub == 0xD then
            -- EDx: Delay Note – stored above; actual play in doEffects

        elseif sub == 0xE then
            -- EEx: Pattern Delay
            patDelay = val
        end
        -- EFx: Invert Loop – not supported by any player, skip
    end
end

-- ───────────────────────────────────────────────────────────────
--  doEffects  (in-between tick processing, currentTick > 0)
-- ───────────────────────────────────────────────────────────────
local function doEffects()
    for channel = 1, mod.numChannels do
        local ch   = channels[channel]
        local note = ch.currentNote
        if not note then goto continue end

        local effect = note.effect
        local param  = note.effectParam
        local ex     = hiNibble(param)
        local ey     = loNibble(param)

        -- ── 0xy Arpeggio ──────────────────────────────────────
        if effect == 0x0 and param ~= 0 then
            -- Relative to the current period, so it also follows slides
            local phase = currentTick % 3
            if phase == 0 then
                setPitchDirect(channel, ch.period)               -- base note
            else
                local idx = nearestNote(ch.ftIdx, ch.period) + ((phase == 1) and ex or ey)
                setPitchDirect(channel, PERIOD_TABLE[ch.ftIdx][math.min(idx, 60)])
            end

        -- ── 1xy Porta Up ──────────────────────────────────────
        elseif effect == 0x1 then
            setChannelPeriod(channel, ch.period - param)

        -- ── 2xy Porta Down ────────────────────────────────────
        elseif effect == 0x2 then
            setChannelPeriod(channel, ch.period + param)

        -- ── 3xy / 5xy Porta To Note (+ optional vol slide) ───
        elseif effect == 0x3 or effect == 0x5 then
            doPortamento(channel)
            if effect == 0x5 then doVolumeSlide(channel) end

        -- ── 4xy / 6xy Vibrato (+ optional vol slide) ─────────
        -- Speed/depth were latched on tick 0 by 4xy only: 6xy's param is the
        -- volume slide and must not overwrite the vibrato settings.
        elseif effect == 0x4 or effect == 0x6 then
            local delta, newPos, newNeg = oscillatorStep(
                ch.vibratoWaveform, ch.vibratoPos, ch.vibratoNeg,
                ch.vibratoSpeed, ch.vibratoDepth, 128)
            ch.vibratoPos = newPos; ch.vibratoNeg = newNeg
            setPitchDirect(channel, ch.period + delta)
            if effect == 0x6 then doVolumeSlide(channel) end

        -- ── 7xy Tremolo ───────────────────────────────────────
        elseif effect == 0x7 then
            local delta, newPos, newNeg = oscillatorStep(
                ch.tremoloWaveform, ch.tremoloPos, ch.tremoloNeg,
                ch.tremoloSpeed, ch.tremoloDepth, 64)
            ch.tremoloPos = newPos; ch.tremoloNeg = newNeg
            -- Apply temporary volume (don't store; tremolo doesn't modify base vol)
            ch.outVolume = math.max(0, math.min(64, ch.volume + delta))

        -- ── Axy Volume Slide ──────────────────────────────────
        elseif effect == 0xA then
            doVolumeSlide(channel)

        -- ── Extended effects ──────────────────────────────────
        elseif effect == 0xE then
            local sub = ex
            local val = ey

            if sub == 0x9 then
                -- E9x: Retrig Note every x ticks (from the sample start)
                if val > 0 and currentTick % val == 0 and ch.sampleNum > 0 then
                    ch.trigSample = ch.sampleNum
                    ch.trigOffset = 0
                end

            elseif sub == 0xC then
                -- ECx: Cut Note (zero volume) at tick x
                if currentTick == val then
                    setChannelVolume(channel, 0)
                end

            elseif sub == 0xD then
                -- EDx: Delay Note – play at tick x
                if currentTick == val and ch.delayNote then
                    local dn = ch.delayNote
                    ch.delayNote = nil
                    triggerSample(channel, dn, 0)
                end
            end
        end

        ::continue::
    end
end

-- ───────────────────────────────────────────────────────────────
--  updateRow  – play all channels for the current row
-- ───────────────────────────────────────────────────────────────
local function updateRow()
    local pattern = mod.patterns[currentPattern]
    local rowData = pattern and pattern[currentRow]
    if not rowData then return end
    for channel = 1, mod.numChannels do
        local note = rowData[channel]
        if note then
            playNote(channel, note)
        end
    end
    if songEnded then
        -- F00: stop at once, like ProTracker.  Sample 0 does not exist, so the
        -- trigger makes every backend silence its voice.
        for channel = 1, mod.numChannels do
            local ch = channels[channel]
            ch.trigSample, ch.trigOffset = 0, 0
            ch.currentNote = nil
        end
    end
end

-- ───────────────────────────────────────────────────────────────
--  advanceRow  – move to the next row, honouring Bxy / Dxy / E6x
-- ───────────────────────────────────────────────────────────────
local function advanceRow()
    if jumpToOrder ~= nil then
        currentPatternIndex = math.min(jumpToOrder + 1, mod.songLength)
        currentPattern      = mod.patternTable[currentPatternIndex]
        currentRow          = (breakToRow or 0) + 1  -- 1-based
        jumpToOrder         = nil
        breakToRow          = nil
    elseif breakToRow ~= nil then
        currentPatternIndex = currentPatternIndex + 1
        if currentPatternIndex > mod.songLength then
            currentPatternIndex = mod.restartPosition + 1
        end
        currentPattern = mod.patternTable[currentPatternIndex]
        currentRow     = breakToRow + 1   -- 0-based → 1-based
        breakToRow     = nil
    elseif loopToRow ~= nil then
        -- E6x Pattern Loop: jump back within the current pattern
        currentRow = loopToRow
        loopToRow  = nil
    else
        -- Normal row advance
        currentRow = currentRow + 1
        if currentRow > 64 then
            currentRow          = 1
            currentPatternIndex = currentPatternIndex + 1
            if currentPatternIndex > mod.songLength then
                currentPatternIndex = mod.restartPosition + 1
            end
            currentPattern = mod.patternTable[currentPatternIndex]
        end
    end
end

-- ───────────────────────────────────────────────────────────────
--  playerTick  – advance the song by exactly one tick (FMODDOC §3.3)
--  Called 2*BPM/5 times per second by the backend.
-- ───────────────────────────────────────────────────────────────
local function playerTick()
    -- Trigger requests last one tick: every consumer (backend, visualiser
    -- mixer) reads the registers after the tick, none of them clears them.
    for c = 1, mod.numChannels do channels[c].trigSample = nil end
    if songEnded then return end
    songTime = songTime + 5 / (2 * bpm)
    currentTick = currentTick + 1

    if currentTick >= ticksPerRow then
        currentTick = 0

        if patDelay > 0 then
            -- Pattern Delay: hold current row, no new notes, but the effects
            -- keep running (§5.30)
            patDelay = patDelay - 1
            doEffects()
        else
            if songStarted then advanceRow() end
            songStarted = true
            updateRow()  -- tick 0 processing (may set jumpToOrder / breakToRow)
        end
    else
        -- In-between ticks: run tick-based effects
        doEffects()
    end
end

-- ═══════════════════════════════════════════════════════════════
--  Backend 1: software mixer (normal LÖVE)
-- ═══════════════════════════════════════════════════════════════
local Mixer = {}
local mixQueue, mixSoundData, mixOut
local mixL, mixR = {}, {}
local mixGain    = 0.5
local tickRemain = 0      -- output frames left until the next player tick

-- ── Visualiser tap (desktop UI only) ─────────────────────────────
-- A mono copy of the output in a ring buffer plus a callback per tick, both
-- stamped with output frame positions, so the UI shows what is being heard.
local vizRing          -- int16 ring buffer (FFI), nil when no UI is attached
local VIZ_RING = 16384 -- ring size in frames (power of two)
local vizFrames = 0    -- frames written so far (also indexes the ring)
local onTickHook       -- function(framePos), called after every player tick

-- Copy mixed frames 1..n into the ring
local function vizWrite(n)
    if not vizRing then return end
    for i = 1, n do
        local v = (mixL[i] + mixR[i]) * 0.5
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        vizRing[(vizFrames + i - 1) % VIZ_RING] = v * 32767
    end
    vizFrames = vizFrames + n
end

-- Decode every sample to floats and reset the voices.  Used by the mixer and,
-- on desktop, by the Source backend to drive the visualisers.
function Mixer.prepare()
    -- Data past the loop end is never played (ProTracker loops back there),
    -- so it is dropped.
    for _, sample in ipairs(mod.samples) do
        if sample.length > 0 then
            local frames = sample.hasLoop and sample.loopEnd or sample.length
            local pcm = {}
            for j = 1, frames do
                local b = string.byte(sample.data, j)
                pcm[j] = ((b < 128) and b or (b - 256)) / 128
            end
            sample.pcm = pcm
        end
    end
    mixGain = 1 / math.sqrt(mod.numChannels)
    tickRemain = 0
    for c = 1, mod.numChannels do
        local ch = channels[c]
        ch.vActive, ch.vPos, ch.vStep, ch.gainL, ch.gainR = false, 0, 0, 0, 0
    end
end

-- Start a fresh output stream (drops anything still queued)
function Mixer.flush()
    if mixQueue then mixQueue:stop() end
    mixQueue = love.audio.newQueueableSource(MIX_RATE, 16, 2, MIX_BUFFERS)
end

function Mixer.load()
    Mixer.prepare()
    Mixer.flush()
    if not mixSoundData then
        mixSoundData = love.sound.newSoundData(MIX_BUFFER, MIX_RATE, 16, 2)
        -- Fast path: write straight into the SoundData memory (LÖVE 11.3+)
        local ok, ffi = pcall(require, "ffi")
        if ok and mixSoundData.getFFIPointer then
            mixOut = ffi.cast("int16_t*", mixSoundData:getFFIPointer())
        end
    end
end

-- Latch one channel's output registers into its voice
function Mixer.commit(c)
    local ch = channels[c]
    if ch.trigSample then
        local sample = mod.samples[ch.trigSample]
        ch.vActive = false
        if sample and sample.pcm then
            ch.vData    = sample.pcm
            ch.vLoopLen = sample.hasLoop and (sample.loopEnd - sample.loopStart) or 0
            ch.vEnd     = #sample.pcm
            local pos = ch.trigOffset
            if pos >= ch.vEnd then
                -- Offset past the end: a looped sample continues in its loop,
                -- anything else is silent (§5.10)
                pos = (ch.vLoopLen > 0) and sample.loopStart or ch.vEnd
            end
            ch.vPos    = pos
            ch.vActive = pos < ch.vEnd
        end
    end
    local period = ch.outPeriod
    ch.vStep = (period > 0) and (AMIGA_CLOCK / clampPeriod(period) / MIX_RATE) or 0
    -- Constant-power pan: hard left/right like Paula, centre at -3 dB per side
    local vol   = ch.outVolume / 64 * mixGain
    local angle = (ch.pan + 1) * math.pi / 4
    ch.gainL = vol * math.cos(angle)
    ch.gainR = vol * math.sin(angle)
end

-- Mix frames first..last of the current buffer
local function mixFrames(first, last)
    local floor = math.floor
    for i = first, last do mixL[i] = 0; mixR[i] = 0 end
    for c = 1, mod.numChannels do
        local ch = channels[c]
        if ch.vActive and ch.vStep > 0 then
            local data, pos, step = ch.vData, ch.vPos, ch.vStep
            local gl, gr = ch.gainL, ch.gainR
            local vEnd, loopLen = ch.vEnd, ch.vLoopLen
            -- Sample that follows the last one: the loop start, or silence
            local wrap = (loopLen > 0) and data[vEnd - loopLen + 1] or 0
            for i = first, last do
                local ip = floor(pos)
                local s  = data[ip + 1]
                if interpolate then
                    s = s + ((data[ip + 2] or wrap) - s) * (pos - ip)
                end
                mixL[i] = mixL[i] + s * gl
                mixR[i] = mixR[i] + s * gr
                pos = pos + step
                if pos >= vEnd then
                    if loopLen > 0 then
                        repeat pos = pos - loopLen until pos < vEnd
                    else
                        ch.vActive = false
                        break
                    end
                end
            end
            ch.vPos = pos
        end
    end
end

-- Render one buffer, running player ticks at their exact sample positions
local function renderBuffer()
    local i = 1
    while i <= MIX_BUFFER do
        if tickRemain <= 0 then
            playerTick()
            for c = 1, mod.numChannels do Mixer.commit(c) end
            if onTickHook then onTickHook(vizFrames + i - 1) end
            tickRemain = tickRemain + MIX_RATE * 5 / (2 * bpm)
        end
        local n = math.min(MIX_BUFFER - i + 1, math.ceil(tickRemain))
        mixFrames(i, i + n - 1)
        i = i + n
        tickRemain = tickRemain - n
    end

    for i = 1, MIX_BUFFER do
        local l, r = mixL[i], mixR[i]
        if l > 1 then l = 1 elseif l < -1 then l = -1 end
        if r > 1 then r = 1 elseif r < -1 then r = -1 end
        if mixOut then
            mixOut[i * 2 - 2] = l * 32767
            mixOut[i * 2 - 1] = r * 32767
        else
            mixSoundData:setSample(i - 1, 1, l)
            mixSoundData:setSample(i - 1, 2, r)
        end
    end
    vizWrite(MIX_BUFFER)
end

function Mixer.update(dt)
    while mixQueue:getFreeBufferCount() > 0 do
        renderBuffer()
        mixQueue:queue(mixSoundData)
    end
    if not mixQueue:isPlaying() then mixQueue:play() end
end

function Mixer.stop()
    mixQueue:pause()   -- keeps the queued audio; play() resumes seamlessly
end

function Mixer.level(c)
    local ch = channels[c]
    return ch.vActive and ch.outVolume / 64 or 0
end

-- Output frame being heard now (to within one buffer)
function Mixer.position()
    local queued = MIX_BUFFERS - mixQueue:getFreeBufferCount()
    return math.max(0, vizFrames - queued * MIX_BUFFER)
end

-- ═══════════════════════════════════════════════════════════════
--  Backend 2: LoveDOS compatibility layer (one Source per sample part)
--
--  LoveDOS Sources offer setVolume/setPitch/setLooping/isPlaying/tell/play/
--  stop – no seek(), clone(), setPosition() or getVolume().  So:
--    * every sample is written as  s<N>.wav  up to its loop end; a loop that
--      starts at 0 simply loops that file (gapless)
--    * a loop starting later gets  s<N>l.wav, started when the head finishes
--      (a gap of up to one frame)
--    * each 9xx offset used by the song gets a pre-cut  s<N>o<xx>.wav
--    * every channel has its own Source objects, so the same sample can play
--      on several channels at once
--  Not reproducible here: panning on LoveDOS, sample-exact timing (ticks run
--  from love.update) and the gapless head → loop transition.
--  File names stay within DOS 8.3 limits.
-- ═══════════════════════════════════════════════════════════════
local Source = {}
local sampleFiles    = {}  -- [sample] = { head, headEnd, headLoops, loop, offsets }
local channelSources = {}  -- [channel][file] = LÖVE Source
local tickAccum      = 0   -- accumulates real time; fires one tick when >= 1

-- Helper function to convert a number to a little-endian byte string
local function toLittleEndian(num, bytes)
    local res = ""
    for i = 1, bytes do
        res = res .. string.char(num % 256)
        num = math.floor(num / 256)
    end
    return res
end

-- Helper function to create a WAV file header
--[[
Positions   Sample Value         Description
1 - 4       "RIFF"               Marks the file as a riff file. Characters are each 1. byte long.
5 - 8       File size (integer)  Size of the overall file - 8 bytes, in bytes (32-bit integer). Typically, you'd fill this in after creation.
9 -12       "WAVE"               File Type Header. For our purposes, it always equals "WAVE".
13-16       "fmt "               Format chunk marker. Includes trailing null
17-20       16                   Length of format data as listed above
21-22       1                    Type of format (1 is PCM) - 2 byte integer
23-24       2                    Number of Channels - 2 byte integer
25-28       44100                Sample Rate - 32 bit integer. Common values are 44100 (CD), 48000 (DAT). Sample Rate = Number of Samples per second, or Hertz.
29-32       176400               (Sample Rate * BitsPerSample * Channels) / 8.
33-34       4                    (BitsPerSample * Channels) / 8.1 - 8 bit mono2 - 8 bit stereo/16 bit mono4 - 16 bit stereo
35-36       16                   Bits per sample
37-40       "data"               "data" chunk header. Marks the beginning of the data section.
41-44       File size (data)     Size of the data section, i.e. file size - 44 bytes header.
]]--
local function createWavHeader(sampleRate, bitsPerSample, numChannels, numSamples)
    local subchunk2Size = numSamples * numChannels * (bitsPerSample / 8)
	local chunkSize = 36 + subchunk2Size
    local byteRate = sampleRate * numChannels * (bitsPerSample / 8)
    local blockAlign = numChannels * (bitsPerSample / 8)

    return table.concat({
        "RIFF",
        toLittleEndian(chunkSize, 4),	-- 32 bit integer (4*8 bytes)
        "WAVE",
        "fmt ",
        toLittleEndian(16, 4),  -- Subchunk1Size
        toLittleEndian(1, 2),   -- AudioFormat (PCM)
        toLittleEndian(numChannels, 2),
        toLittleEndian(sampleRate, 4),
        toLittleEndian(byteRate, 4),
        toLittleEndian(blockAlign, 2),
        toLittleEndian(bitsPerSample, 2),
        "data",
        toLittleEndian(subchunk2Size, 4)
    })
end

-- 8-bit signed (MOD) → 8-bit unsigned (WAV) lookup
local UNSIGNED = {}
for b = 0, 255 do UNSIGNED[b] = string.char((b + 128) % 256) end

local function toUnsigned(data)
    local out, n = {}, 0
    for a = 1, #data, 1024 do  -- chunked: string.byte returns values on the stack
        local bytes = { string.byte(data, a, math.min(a + 1023, #data)) }
        for k = 1, #bytes do
            n = n + 1
            out[n] = UNSIGNED[bytes[k]]
        end
    end
    return table.concat(out)
end

-- Write unsigned 8-bit PCM as <name>.wav (Amiga C-2 base: 8363 Hz at period 428)
local function writeWav(name, pcm)
    local file = name .. ".wav"
    local wavData = createWavHeader(8363, 8, 1, #pcm) .. pcm
    love.filesystem.write(file, wavData, #wavData)
    return file
end

-- Collect every (sample, 9xx) pair the song uses, walking the order list
local function scanSampleOffsets()
    local used, lastSample, lastParam = {}, {}, {}
    for o = 1, mod.songLength do
        local pattern = mod.patterns[mod.patternTable[o]]
        for row = 1, (pattern and 64 or 0) do
            for c = 1, mod.numChannels do
                local note = pattern[row][c]
                if note.sample > 0 then lastSample[c] = note.sample end
                if note.effect == 0x9 and note.period > 0 then
                    if note.effectParam > 0 then lastParam[c] = note.effectParam end
                    local s, p = lastSample[c], lastParam[c]
                    if s and p then
                        used[s] = used[s] or {}
                        used[s][p] = true
                    end
                end
            end
        end
    end
    return used
end

function Source.load()
    pcall(love.audio.setDistanceModel, "none")  -- desktop LÖVE: pan without attenuation
    sampleFiles, tickAccum = {}, 0
    if vizRing then Mixer.prepare() end         -- silent mix for the visualisers
    local offsets = scanSampleOffsets()
    for i, sample in ipairs(mod.samples) do
        if sample.length > 0 then
            local pcm     = toUnsigned(sample.data)
            local headEnd = sample.hasLoop and sample.loopEnd or sample.length
            local entry   = { head = writeWav("s" .. i, pcm:sub(1, headEnd)), headEnd = headEnd, offsets = {} }
            if sample.hasLoop then
                if sample.loopStart == 0 then
                    entry.headLoops = true
                else
                    entry.loop = writeWav("s" .. i .. "l", pcm:sub(sample.loopStart + 1, sample.loopEnd))
                end
            end
            for p in pairs(offsets[i] or {}) do
                if p * 256 < headEnd then
                    entry.offsets[p] = writeWav("s" .. i .. "o" .. p, pcm:sub(p * 256 + 1, headEnd))
                end
            end
            sampleFiles[i] = entry
        end
    end
    for c = 1, mod.numChannels do channelSources[c] = {} end
end

-- Helper: apply a pan value (-1..+1) to a LÖVE source (desktop LÖVE only).
-- The source sits on a unit circle in front of the listener: with the distance
-- model disabled only the direction counts, so (pan, 0, 0) alone would make any
-- non-zero pan hard left/right.  Wrapped in pcall: LoveDOS has no 3D audio.
local function applyPan(source, pan)
    pcall(function()
        source:setRelative(true)
        source:setPosition(pan, 0, -math.sqrt(1 - pan * pan))
    end)
end

-- Push the channel's output registers to its Source (only what changed)
local function applySource(ch)
    local src = ch.src
    local period = clampPeriod(ch.outPeriod > 0 and ch.outPeriod or 428)
    if period ~= ch.srcPeriod then
        src:setPitch(428 / period)
        ch.srcPeriod = period
    end
    if ch.outVolume ~= ch.srcVolume then
        src:setVolume(ch.outVolume / 64)
        ch.srcVolume = ch.outVolume
    end
    if ch.pan ~= ch.srcPan then
        applyPan(src, ch.pan)
        ch.srcPan = ch.pan
    end
end

local function startSource(c, file, looping)
    local ch  = channels[c]
    local src = channelSources[c][file]
    if not src then
        src = love.audio.newSource(file, "static")
        channelSources[c][file] = src
    end
    src:stop()              -- also rewinds
    src:setLooping(looping)
    ch.src = src
    ch.srcPeriod, ch.srcVolume, ch.srcPan = nil, nil, nil
    applySource(ch)
    src:play()
end

function Source.commit(c)
    local ch = channels[c]
    if ch.trigSample then
        local entry = sampleFiles[ch.trigSample]
        local param = math.floor(ch.trigOffset / 256)
        if ch.src then ch.src:stop() end
        ch.src, ch.srcNext = nil, nil
        if entry then
            local loopFile = entry.loop or (entry.headLoops and entry.head) or nil
            if param > 0 and entry.offsets[param] then
                startSource(c, entry.offsets[param], false)
                ch.srcNext = loopFile
            elseif param > 0 and param * 256 >= entry.headEnd then
                -- Offset past the end: loop part only, or silence (§5.10)
                if loopFile then startSource(c, loopFile, true) end
            else
                startSource(c, entry.head, entry.headLoops or false)
                ch.srcNext = entry.loop
            end
        end
    end
    if ch.src then applySource(ch) end
end

-- Desktop UI: mix the tick silently, only to feed the scope and spectrum
local shadowRemain = 0
local function shadowMix()
    for c = 1, mod.numChannels do Mixer.commit(c) end
    shadowRemain = shadowRemain + MIX_RATE * 5 / (2 * bpm)
    local n = math.floor(shadowRemain)
    shadowRemain = shadowRemain - n
    while n > 0 do
        local k = math.min(n, MIX_BUFFER)
        mixFrames(1, k)
        vizWrite(k)
        n = n - k
    end
end

function Source.update(dt)
    tickAccum = tickAccum + dt * (2 * bpm / 5)   -- ticks per second (125 BPM → 50)
    while tickAccum >= 1 do
        tickAccum = tickAccum - 1
        playerTick()
        for c = 1, mod.numChannels do Source.commit(c) end
        if vizRing then
            if onTickHook then onTickHook(vizFrames) end
            shadowMix()
        end
    end

    -- Head finished → continue with the looping part
    for c = 1, mod.numChannels do
        local ch = channels[c]
        if ch.srcNext and ch.src and not ch.src:isPlaying() then
            local nextFile = ch.srcNext
            ch.srcNext = nil
            startSource(c, nextFile, true)
        end
    end
end

function Source.stop()
    for c = 1, mod.numChannels do
        local ch = channels[c]
        if ch.src then ch.src:stop() end
        ch.src, ch.srcNext = nil, nil
    end
end

function Source.level(c)
    local ch = channels[c]
    return (ch.src and ch.src:isPlaying()) and ch.outVolume / 64 or 0
end

Source.flush = Source.stop

-- Sources start right away, so the newest tick is the one being heard
function Source.position()
    return vizFrames
end


-- ═══════════════════════════════════════════════════════════════
--  Shared helpers
-- ═══════════════════════════════════════════════════════════════

local function periodToNote(period)
    local notes = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
    local row = PERIOD_TABLE[1]
    for j = 1, 60 do
        if period >= row[j] then
            return notes[(j - 1) % 12 + 1] .. tostring(math.floor((j - 1) / 12))
        end
    end
    return nil
end

-- Reset all playback state to the start of the song
local function startSong()
    for _, sample in ipairs(mod.samples) do
        sample.finetune = sample.baseFinetune
    end
    initializeChannels()
    ticksPerRow, bpm = 6, 125
    jumpToOrder, breakToRow, loopToRow, patDelay = nil, nil, nil, 0
    -- Prime the player: tick starts at SPEED so the first tick plays row 1
    -- (FMODDOC §3.3)
    currentPatternIndex = 1
    currentPattern = mod.patternTable[currentPatternIndex]
    currentRow = 1
    currentTick = ticksPerRow
    songStarted, songEnded = false, false
    songTime, tickRemain, shadowRemain = 0, 0, 0
end

-- ═══════════════════════════════════════════════════════════════
--  LoveDOS screen: the original plain-text display
-- ═══════════════════════════════════════════════════════════════

local function drawLoveDOS()
    love.graphics.print("MOD Player", 10, 10)
    love.graphics.print("Pattern: " .. currentPattern, 10, 30)
    love.graphics.print("Row: " .. currentRow-1, 10, 50)
    love.graphics.print(songEnded and "Song ended - Space restarts" or ("Tick: " .. currentTick), 10, 70)

    local pattern = mod.patterns[currentPattern]
    local rowData = pattern and pattern[currentRow]

    -- Draw a simple visualization
    love.graphics.setColor(255, 255, 255)
    for i = 1, mod.numChannels do
        local height = backend.level(i) * 100
        love.graphics.rectangle("fill", (i-1) * 30 + 10, 110, 20, height)

		local note = rowData and rowData[i]
		local noteStr = note and periodToNote(note.period) or "---"
		love.graphics.print(noteStr, (i-1) * 30 + 10, 90)
    end
end

local function togglePlayLoveDOS()
    if songEnded then
        -- Song stopped by F00: Space plays it again from the start
        startSong()
        play = true
        return
    end
    play = not play
    if not play then
        backend.stop()
    end
end

-- ═══════════════════════════════════════════════════════════════
--  Desktop front end: retro UI (ui.lua), file browser, playlist
-- ═══════════════════════════════════════════════════════════════

local ui, fsb  -- desktop-only modules, loaded in love.load

-- Everything the UI shows
local app = {
    mod         = nil,
    playing     = false,
    scanlines   = true,
    interpolate = false,
    mixer       = USE_SOFTWARE_LOOP,
    folder      = nil,   -- folder of the current playlist
    tracks      = {},    -- MOD files in that folder (full paths)
    track       = 0,     -- index into tracks
    songName    = "",
    message     = nil,
    noteName    = periodToNote,
    browser     = { open = false, dir = nil, title = "", items = {}, sel = 1, scroll = 0 },
}
local messageTimer = 0

local function say(msg)
    app.message, messageTimer = msg, 3
end

-- Display state after a tick, stamped with the output frame it is heard at
local function snapshot(pos)
    local s = {
        pos = pos, order = currentPatternIndex, pattern = currentPattern, row = currentRow,
        speed = ticksPerRow, bpm = bpm, time = songTime, ended = songEnded,
        hit = {}, vol = {}, instr = {}, active = {},
    }
    for c = 1, mod.numChannels do
        local ch = channels[c]
        s.hit[c]    = (ch.trigSample or 0) > 0
        s.vol[c]    = ch.outVolume
        s.instr[c]  = ch.lastSample
        s.active[c] = ch.vActive or false
    end
    return s
end

-- ── Settings (save directory) ────────────────────────────────────
local SETTINGS = "settings.txt"

local function loadSettings()
    local s = {}
    local data = love.filesystem.read(SETTINGS)
    if data then
        for k, v in data:gmatch("([%w_]+)=([^\n]*)") do s[k] = v end
    end
    return s
end

local function saveSettings()
    love.filesystem.write(SETTINGS, table.concat({
        "folder=" .. (app.folder or ""),
        "track=" .. (app.tracks[app.track] and fsb.basename(app.tracks[app.track]) or ""),
        "scanlines=" .. tostring(app.scanlines),
        "interpolate=" .. tostring(app.interpolate),
    }, "\n") .. "\n")
end

-- ── Playback ─────────────────────────────────────────────────────
-- "song.mod" and the Amiga style "mod.song"
local function isMOD(name)
    name = name:lower()
    return name:match("%.mod$") ~= nil or name:match("^mod%.") ~= nil
end

local function setPlaying(on)
    play, app.playing = on, on
    if not on and backend then backend.stop() end
end

-- Back to the start of the song, dropping audio that is still queued
local function restart()
    backend.flush()
    startSong()
    ui.reset(backend.position(), snapshot(backend.position()))
end

local function playSongData(data, name)
    local ok, newMod = pcall(parseMOD, data)
    if not ok then say(name .. ": " .. tostring(newMod)); return false end
    if backend then backend.stop() end
    mod = newMod
    startSong()
    backend = USE_SOFTWARE_LOOP and Mixer or Source
    backend.load()
    app.mod, app.songName = mod, name
    ui.reset(backend.position(), snapshot(backend.position()))
    return true
end

local function scanFolder(dir)
    local dirs, files = fsb.list(dir)
    if not dirs then return nil end
    local tracks = {}
    for _, f in ipairs(files) do
        if isMOD(f) then tracks[#tracks + 1] = fsb.join(dir, f) end
    end
    return tracks
end

local function playTrack(i)
    local path = app.tracks[i]
    if not path then return false end
    local data, err = fsb.read(path)
    if not data then say(err); return false end
    if not playSongData(data, fsb.basename(path)) then return false end
    app.track = i
    saveSettings()
    return true
end

local function stepTrack(d)
    local n = #app.tracks
    if n == 0 then return end
    for k = 1, n do                       -- skip files that fail to load
        if playTrack((app.track - 1 + d * k) % n + 1) then return end
    end
end

-- Use `dir` as the playlist folder and play `file` (or its first song)
local function openFolder(dir, file)
    local tracks = scanFolder(dir)
    if not tracks then say("Cannot open " .. dir); return false end
    if #tracks == 0 then say("No MOD files in " .. fsb.basename(dir)); return false end
    app.folder, app.tracks = dir, tracks
    local idx = 1
    for i, t in ipairs(tracks) do
        if file and fsb.basename(t):lower() == file:lower() then idx = i end
    end
    return playTrack(idx)
end

-- ── File browser ─────────────────────────────────────────────────
local browser = app.browser

local function browse(dir)
    local items = {}
    if dir == nil then                    -- top level: drive list
        for _, d in ipairs(fsb.drives()) do items[#items + 1] = { kind = "drive", name = d, path = d } end
        browser.title = "DRIVES"
    else
        local dirs, files = fsb.list(dir)
        if not dirs then say("Cannot open " .. dir); return end
        if fsb.parent(dir) or fsb.isWindows then items[1] = { kind = "up" } end
        for _, d in ipairs(dirs) do items[#items + 1] = { kind = "dir", name = d, path = fsb.join(dir, d) } end
        for _, f in ipairs(files) do
            if isMOD(f) then items[#items + 1] = { kind = "file", name = f, path = fsb.join(dir, f) } end
        end
        browser.title = dir
    end
    local from = browser.dir
    browser.dir, browser.items, browser.sel, browser.scroll = dir, items, 1, 0
    -- Coming back up: select the folder we came from; else the current song.
    for i, it in ipairs(items) do
        if (from and it.path == from) or (it.kind == "file" and it.path == app.tracks[app.track]) then
            browser.sel = i
        end
    end
    browser.scroll = math.max(0, browser.sel - ui.browserRows())
end

local function moveSel(d)
    local n = #browser.items
    if n == 0 then return end
    browser.sel = math.max(1, math.min(n, browser.sel + d))
    local rows = ui.browserRows()
    if browser.sel <= browser.scroll then browser.scroll = browser.sel - 1 end
    if browser.sel > browser.scroll + rows then browser.scroll = browser.sel - rows end
end

local function activate()
    local it = browser.items[browser.sel]
    if not it then return end
    if it.kind == "up" then browse(fsb.parent(browser.dir))
    elseif it.kind == "dir" or it.kind == "drive" then browse(it.path)
    elseif openFolder(browser.dir, it.name) then
        browser.open = false
        setPlaying(true)
    end
end

local function toggleBrowser()
    browser.open = not browser.open
    if browser.open then browse(app.folder or fsb.gameFolder()) end
end

local function keypressedDesktop(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        ui.resize(love.graphics.getDimensions())
        return
    end

    if browser.open then
        if key == "escape" or key == "tab" then browser.open = false
        elseif key == "up" then moveSel(-1)
        elseif key == "down" then moveSel(1)
        elseif key == "pageup" then moveSel(-ui.browserRows())
        elseif key == "pagedown" then moveSel(ui.browserRows())
        elseif key == "home" then moveSel(-#browser.items)
        elseif key == "end" then moveSel(#browser.items)
        elseif key == "return" or key == "kpenter" or key == "right" then activate()
        elseif key == "backspace" or key == "left" then
            if browser.dir then browse(fsb.parent(browser.dir)) end
        end
        return
    end

    if key == "escape" then
        love.event.quit()
    elseif key == "tab" or key == "b" then
        toggleBrowser()
    elseif not mod then
        return
    elseif key == "space" then
        if songEnded then
            restart()
            setPlaying(true)
        else
            setPlaying(not play)
        end
    elseif key == "right" then stepTrack(1)
    elseif key == "left" then stepTrack(-1)
    elseif key == "r" then restart()
    elseif key == "i" then
        interpolate = not interpolate
        app.interpolate = interpolate
        if USE_SOFTWARE_LOOP then
            say(interpolate and "Linear interpolation on" or "Interpolation off (raw like Paula)")
        else
            say("Interpolation only affects the mixer (USE_SOFTWARE_LOOP = true)")
        end
        saveSettings()
    elseif key == "s" then
        app.scanlines = not app.scanlines
        saveSettings()
    end
end

local function loadDesktop(arg)
    local ffi = require("ffi")
    ui  = require("ui")
    fsb = require("fsbrowse")
    vizRing = ffi.new("int16_t[?]", VIZ_RING)
    onTickHook = function(pos) ui.pushTick(snapshot(pos)) end
    ui.load(vizRing, VIZ_RING, MIX_RATE)
    ui.reset(0, nil)

    local s = loadSettings()
    app.scanlines   = s.scanlines ~= "false"
    app.interpolate = (s.interpolate == "true") or MIX_INTERPOLATE
    interpolate     = app.interpolate
    setPlaying(false)

    -- A file on the command line, else the last folder, else DEFAULT_MOD
    local game = fsb.gameFolder()
    local file = type(arg) == "table" and type(arg[1]) == "string" and arg[1]
    local opened = false
    if file and isMOD(fsb.basename(file)) then
        local path = fsb.normalize(file)
        if not (path:match("^%a:") or path:sub(1, 1) == "/") then path = fsb.join(game, path) end
        opened = openFolder(fsb.parent(path), fsb.basename(path))
    end
    if not opened and s.folder and s.folder ~= "" then
        opened = openFolder(s.folder, s.track)
    end
    if not opened then
        local dir = DEFAULT_MOD:match("^(.*)/[^/]+$")
        opened = openFolder(dir and fsb.join(game, fsb.normalize(dir)) or game, fsb.basename(DEFAULT_MOD))
    end
    if not opened then
        -- No MOD files in MUSIC/ (e.g. a fresh clone): play the demo song.
        -- Read through love.filesystem, so it is found inside a .love file too.
        local data = love.filesystem.read(DEMO_MOD)
        opened = data ~= nil and playSongData(data, DEMO_MOD)
        app.message = nil
        if opened then
            say("No MOD in MUSIC/ - playing the demo song. TAB: browse")
        else
            toggleBrowser()
            say("Pick a folder with MOD files")
        end
    end
    if opened then setPlaying(true) end
end

-- ═══════════════════════════════════════════════════════════════
--  LÖVE callbacks
-- ═══════════════════════════════════════════════════════════════

-- tick driver: love.update
function love.update(dt)
    if play and backend then backend.update(dt) end
    if ui then
        ui.update(dt, backend and backend.position() or 0)
        if messageTimer > 0 then
            messageTimer = messageTimer - dt
            if messageTimer <= 0 then app.message = nil end
        end
    end
end

function love.draw()
    if ui then ui.draw(app) else drawLoveDOS() end
end

function love.keypressed(key)
    if ui then return keypressedDesktop(key) end
    if key == "escape" then
        love.event.quit()
    end
	if key == "space" then
        togglePlayLoveDOS()
    end
end

function love.resize(w, h)
    if ui then ui.resize(w, h) end
end

function love.wheelmoved(_, y)
    if ui and browser.open then moveSel(-y * 3) end
end

local lastClick, lastIndex = 0, nil

function love.mousepressed(x, y, button)
    if not ui or not browser.open or button ~= 1 then return end
    local i = ui.browserHit(browser, ui.toCanvas(x, y))
    if not i then return end
    local now = love.timer.getTime()
    browser.sel = i
    if lastIndex == i and now - lastClick < 0.4 then activate() end
    lastClick, lastIndex = now, i
end

-- Drop a folder: play it.  Drop a MOD file: play its folder from that file.
function love.directorydropped(path)
    path = fsb.normalize(path)
    if openFolder(path) then
        browser.open = false
        setPlaying(true)
    else
        browser.open = true
        browse(path)
    end
end

function love.filedropped(file)
    local path = fsb.normalize(file:getFilename())
    if not isMOD(fsb.basename(path)) then say("Not a MOD file"); return end
    local dir = fsb.parent(path)
    if dir and openFolder(dir, fsb.basename(path)) then
        browser.open = false
        setPlaying(true)
    end
end

function love.quit()
    if ui then saveSettings() end
end

-- LÖVE-DOS callback functions
function love.load(arg)
    if not IS_LOVEDOS then return loadDesktop(arg) end
    local file = DEFAULT_MOD
    if type(arg) == "table" and type(arg[1]) == "string" and arg[1]:lower():match("%.mod$") then
        file = arg[1]
    end
    local ok, data = pcall(love.filesystem.read, file)
    if not (ok and data) then
        print("Info: " .. file .. " not found - playing " .. DEMO_MOD)
        data = love.filesystem.read(DEMO_MOD)
    end
    mod = parseMOD(data) -- Load your MOD file
    startSong()
    backend = USE_SOFTWARE_LOOP and Mixer or Source
    backend.load()
end
