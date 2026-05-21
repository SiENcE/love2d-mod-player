-- Complete MOD Player Implementation for LÖVE-DOS
--local bit32 = require "bit32"
--local PERIOD_TABLE = require "periodtable"

-- Complete MOD Player Implementation for LÖVE-DOS
local bit32 = {}

local N = 32
local P = 2^N

function bit32.bnot(x)
	x = x % P
	return P - 1 - x
end

function bit32.band(x, y)
	-- Common usecases, they deserve to be optimized
	if y == 0xff then return x % 0x100 end
	if y == 0xffff then return x % 0x10000 end
	if y == 0xffffffff then return x % 0x100000000 end
	
	x, y = x % P, y % P
	local r = 0
	local p = 1
	for i = 1, N do
		local a, b = x % 2, y % 2
		x, y = math.floor(x / 2), math.floor(y / 2)
		if a + b == 2 then
			r = r + p
		end
		p = 2 * p
	end
	return r
end

function bit32.bor(x, y)
	-- Common usecases, they deserve to be optimized
	if y == 0xff then return x - (x%0x100) + 0xff end
	if y == 0xffff then return x - (x%0x10000) + 0xffff end
	if y == 0xffffffff then return 0xffffffff end
	
	x, y = x % P, y % P
	local r = 0
	local p = 1
	for i = 1, N do
		local a, b = x % 2, y % 2
		x, y = math.floor(x / 2), math.floor(y / 2)
		if a + b >= 1 then
			r = r + p
		end
		p = 2 * p
	end
	return r
end

function bit32.bxor(x, y)
	x, y = x % P, y % P
	local r = 0
	local p = 1
	for i = 1, N do
		local a, b = x%2, y%2
		x, y = math.floor(x/2), math.floor(y/2)
		if a + b == 1 then
			r = r + p
		end
		p = 2 * p
	end
	return r
end

function bit32.lshift(x, s_amount)
	if math.abs(s_amount) >= N then return 0 end
	x = x % P
	if s_amount < 0 then
		return math.floor(x * (2 ^ s_amount))
	else
		return (x * (2 ^ s_amount)) % P
	end
end

function bit32.rshift(x, s_amount)
	if math.abs(s_amount) >= N then return 0 end
	x = x % P
	if s_amount > 0 then
		return math.floor(x * (2 ^ - s_amount))
	else
		return (x * (2 ^ -s_amount)) % P
	end
end

function bit32.arshift(x, s_amount)
	if math.abs(s_amount) >= N then return 0 end
	x = x % P
	if s_amount > 0 then
		local add = 0
		if x >= P/2 then
			add = P - 2 ^ (N - s_amount)
		end
		return math.floor(x * (2 ^ -s_amount)) + add
	else
		return (x * (2 ^ -s_amount)) % P
	end
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
local tickAccum = 0    -- Accumulates real time; fires one tick when >= 1/tickRate
local sampleRate = 44100
local bufferSize = 4096 -- Adjust based on LÖVE-DOS requirements
local channels = {}
local sampleSources = {}
local play = false

-- When true: track sample-frame position per channel each tick and seek with the
-- pitch-corrected formula.  Eliminates loop drift at all pitches.
-- Set to false for LoveDOS / low-CPU targets, which fall back to the coarser
-- tell()-based poll (drifts at pitches ≠ C-2 but costs almost nothing).
local USE_SOFTWARE_LOOP = true

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
local patDelay     = 0     -- EEx: how many extra "row holds" remain
local loopRow      = {}    -- E6x per channel: stored loop-start row (1-based)
local loopCount    = {}    -- E6x per channel: remaining loop iterations

-- Amiga default channel panning.
-- Pattern repeats every 4: Left, Right, Right, Left (hard-panned as on original hardware).
-- Value range: -1.0 (full left) to +1.0 (full right).
local AMIGA_PAN = { -1.0, 1.0, 1.0, -1.0 }

-- Helper: apply a pan value (-1..+1) to a LÖVE source.
-- Uses source:setPosition(x, 0, 0) with distance model disabled so volume doesn't attenuate.
-- Wrapped in pcall so it silently degrades on LoveDOS where 3D audio may be absent.
local function applyPan(source, pan)
    if not source then return end
    pcall(function()
        love.audio.setDistanceModel("none")
        source:setPosition(pan, 0, 0)
        source:setRelative(true)
    end)
end

-- MOD File Loader and Parser for LÖVE-DOS
local function readString(data, offset, length)
    return string.sub(data, offset, offset + length - 1)
end

local function readUint16(data, offset)
    local b1, b2 = string.byte(data, offset, offset + 1)
    return b1 * 256 + b2
end
local function readUint16BigEndian(data, offset)
    -- Extract the two bytes starting from the offset
    local byte1 = string.byte(data, offset)     -- Most significant byte (MSB)
    local byte2 = string.byte(data, offset + 1) -- Least significant byte (LSB)

    -- Combine them into a 16-bit unsigned integer (big-endian)
    local value = byte1 * 256 + byte2

    return value
end

local function readUint8(data, offset)
    return string.byte(data, offset)
end

local function parseSample(fileData, offset)
    local sample = {}
    sample.name = readString(fileData, offset, 22)  -- Read sample name (22 bytes)
    sample.length = readUint16BigEndian(fileData, offset + 22) * 2 -- Read sample length (2 bytes) and convert to bytes
    local ft = readUint8(fileData, offset + 24)
    ft = bit32.band(ft, 0x0F) -- lower 4 bits only
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
                local noteData = {}
                local byte1 = readUint8(data, offset)
                local byte2 = readUint8(data, offset + 1)
                local byte3 = readUint8(data, offset + 2)
                local byte4 = readUint8(data, offset + 3)

				if byte1 == nil then break end

                -- Updated bitwise operations
                noteData.sample = bit32.bor(bit32.band(byte1, 0xF0), bit32.rshift(byte3, 4))
                noteData.period = bit32.bor(bit32.lshift(bit32.band(byte1, 0x0F), 8), byte2)
                noteData.effect = bit32.band(byte3, 0x0F)
                noteData.effectParam = byte4

                rowData[channel] = noteData
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
local function loadMOD(filename)
    local fileData = love.filesystem.read(filename)
    if not fileData then
        error("Failed to load MOD file: " .. filename)
    end
    
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

    if magicBytes == "M.K." or magicBytes == "M!K!" or magicBytes == "FLT4" then
        numChannels = 4
    elseif magicBytes == "FLT8" then
        numChannels = 8
    elseif magicBytes == "6CHN" then
        numChannels = 6
    elseif magicBytes == "8CHN" then
        numChannels = 8
    elseif string.sub(magicBytes, 1, 2) == "CH" or
           string.sub(magicBytes, 3, 4) == "CH" then
        -- e.g. "10CH", "12CH" … "32CH"
        local n = tonumber(string.sub(magicBytes, 1, 2))
               or tonumber(string.sub(magicBytes, 1, 1))
        numChannels = n or 4
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

    -- Read pattern order table (128 bytes follow song-length byte)
    mod.patternTable = {}
    local highestPattern = 0
    for i = 1, 128 do
        mod.patternTable[i] = readUint8(fileData, songLenOff + 1 + i)
        highestPattern = math.max(highestPattern, mod.patternTable[i])
    end

    -- Parse patterns
    mod.patterns = parsePatterns(fileData, patternBase, highestPattern + 1, numChannels)

    -- Parse sample data
    local sampleDataOffset = patternBase + (highestPattern + 1) * 64 * numChannels * 4
    for i, sample in ipairs(mod.samples) do
        sample.data = readString(fileData, sampleDataOffset, sample.length)
        sampleDataOffset = sampleDataOffset + sample.length
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
            source      = nil,
            period      = 0,        -- current base period (Amiga value)
            volume      = 0,        -- current base volume (0-64)
            pan         = pan,
            lastSample  = 0,        -- last triggered sample number (1-31)
            noteIdx     = 1,        -- period-table index of current note (1-60)
            ftIdx       = 1,        -- finetune row index in PERIOD_TABLE (1-16)
            -- Portamento (effects 1,2,3,5)
            portaTarget = 0,        -- target period for effect 3
            portaSpeed  = 0,        -- speed for effects 1,2,3
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
            -- Arpeggio (effect 0)
            arpX = 0,
            arpY = 0,
            -- Delay note (EDx)
            delayNote = nil,
            delayTick = 0,
            -- Loop state (set from sampleSources when a sample is triggered)
            hasLoop        = false,
            loopStart      = 0,   -- seconds  (LoveDOS fallback)
            loopEnd        = 0,   -- seconds  (LoveDOS fallback)
            loopStartFrame = 0,   -- raw sample frames
            loopEndFrame   = 0,   -- raw sample frames
            sampleFramePos = 0,   -- running frame counter for software-loop tracking
            -- Current row's note (used by doEffects on in-between ticks)
            currentNote = nil,
        }
        loopRow[i]   = 0
        loopCount[i] = 0
    end
end

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
    --local chunkSize = 36 + subchunk2Size
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

local function loadSamples()
    for i, sample in ipairs(mod.samples) do

        if sample.data and sample.length > 0 then

            -- Create WAV header (Amiga C-2 base: 8363 Hz at period 428)
            local header = createWavHeader(8363, 8, 1, sample.length)

            -- Convert 8-bit signed PCM to 8-bit unsigned PCM
            local convertedData = {}
            for j = 1, sample.length do
                if (string.byte(sample.data, j) == nil) then
                    print('Warning: sample data is nil (sample,pos,byte,length):', i, j, string.byte(sample.data, j), sample.length)
                    break
                end
                convertedData[j] = string.char( (string.byte(sample.data, j) + 128) % 256 )
            end
            local sampleData = table.concat(convertedData)

            local wavData = header .. sampleData

            -- this is for LoveDos, as newSource must be loaded from disk
            local tempFile = i .. ".wav"
            love.filesystem.write(tempFile, wavData, #wavData)
            -- Load the sample as an audio source
            local src = love.audio.newSource(tempFile, "static")

            -- MOD loop convention: loopLength > 2 bytes means the sample loops.
            -- Store loop boundaries both in seconds (LoveDOS fallback) and in raw
            -- sample frames (accurate software-loop path).
            local hasLoop = sample.loopLength > 2
            sampleSources[i] = {
                source         = src,
                hasLoop        = hasLoop,
                loopStart      = sample.loopStart / 8363,                       -- seconds (LoveDOS fallback)
                loopEnd        = (sample.loopStart + sample.loopLength) / 8363, -- seconds (LoveDOS fallback)
                loopStartFrame = sample.loopStart,                              -- raw sample frames
                loopEndFrame   = sample.loopStart + sample.loopLength,          -- raw sample frames
            }
			--print(sampleSources[i].hasLoop,sampleSources[i].loopStart,sampleSources[i].loopEnd)

            -- Remove the temporary file
            -- not supported by LoveDOS
--            love.filesystem.remove(tempFile)
        else
            sampleSources[i] = nil  -- Empty sample
        end
    end
end

--[[
local function loadSamples()
    for i, sample in ipairs(mod.samples) do

        if sample.data and sample.length > 0 then
            -- Load the sample as an audio source
            sampleSources[i] = love.audio.newSource(i .. ".wav", "static")
        else
            sampleSources[i] = nil  -- Empty sample
        end
    end
end
]]--

-- ───────────────────────────────────────────────────────────────
--  Low-level channel helpers
-- ───────────────────────────────────────────────────────────────

-- Clamp and apply a volume (0-64) to a channel's source and store it.
local function setChannelVolume(ch, vol)
    vol = math.max(0, math.min(64, math.floor(vol)))
    channels[ch].volume = vol
    if channels[ch].source then
        channels[ch].source:setVolume(vol / 64)
    end
end

-- Store a new base period for a channel and update its source pitch.
-- Does NOT modify the "in-flight" period (e.g. during vibrato).
local function setChannelPeriod(ch, period)
    period = math.max(54, math.min(1712, math.floor(period)))
    channels[ch].period = period
    if channels[ch].source then
        channels[ch].source:setPitch(428 / period)
    end
end

-- Apply a transient pitch offset (vibrato/arpeggio) without storing it.
local function setPitchDirect(ch, period)
    period = math.max(54, math.min(1712, math.floor(period)))
    if channels[ch].source then
        channels[ch].source:setPitch(428 / period)
    end
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
    local cur = channels[ch].period
    local tgt = channels[ch].portaTarget
    local spd = channels[ch].portaSpeed
    if tgt == 0 or cur == tgt then return end
    if cur < tgt then
        cur = math.min(cur + spd, tgt)
    else
        cur = math.max(cur - spd, tgt)
    end
    -- Glissando: snap to nearest semitone in the finetune table
    if channels[ch].glissando then
        local ft = channels[ch].ftIdx
        local best = 1
        local bestDiff = math.huge
        for i = 1, 60 do
            local d = math.abs(PERIOD_TABLE[ft][i] - cur)
            if d < bestDiff then bestDiff = d; best = i end
        end
        cur = PERIOD_TABLE[ft][best]
    end
    setChannelPeriod(ch, cur)
end

-- ───────────────────────────────────────────────────────────────
--  triggerSample: start/restart sample playback for a channel.
--  Called from playNote (tick 0) and doEffects (EDx delay).
-- ───────────────────────────────────────────────────────────────
local function triggerSample(channel, note, seekBytes)
    seekBytes = seekBytes or 0
    local ch = channels[channel]

    -- Determine which sample number to use
    local sampleNum = (note.sample > 0) and note.sample or ch.lastSample
    if not sampleNum or sampleNum <= 0 or sampleNum > 31 then return end
    local sampleEntry = sampleSources[sampleNum]
    if not sampleEntry then return end

    -- Stop previous source
    if ch.source then ch.source:stop() end

    -- Clone or share the underlying LÖVE source
    local baseSrc = sampleEntry.source
    if baseSrc.clone then
        ch.source = baseSrc:clone()
    else
        ch.source = baseSrc
    end

    -- Store loop boundaries for both the accurate (frame) and fallback (seconds) paths.
    ch.hasLoop        = sampleEntry.hasLoop
    ch.loopStart      = sampleEntry.loopStart
    ch.loopEnd        = sampleEntry.loopEnd
    ch.loopStartFrame = sampleEntry.loopStartFrame
    ch.loopEndFrame   = sampleEntry.loopEndFrame
    -- Reset the frame counter; seekBytes offset is applied below via source:seek()
    -- so the counter starts there too.
    ch.sampleFramePos = seekBytes

    -- Apply current channel volume
    ch.source:setVolume(ch.volume / 64)

    -- Determine finetune and closest note index
    local sample  = mod.samples[sampleNum]
    local finetune = sample.finetune or 0
    local ft_idx   = (finetune >= 0) and (finetune + 1) or (finetune + 17)
    ch.ftIdx = ft_idx

    local bestIdx  = 1
    local bestDiff = math.huge
    for i = 1, 60 do
        local d = math.abs(PERIOD_TABLE[1][i] - note.period)
        if d < bestDiff then bestDiff = d; bestIdx = i end
    end
    ch.noteIdx = bestIdx

    -- Set pitch using the finetune-adjusted period
    local tunedPeriod = PERIOD_TABLE[ft_idx][bestIdx]
    ch.period = tunedPeriod
    ch.source:setPitch(428 / tunedPeriod)

    -- Reset vibrato/tremolo phase if waveform < 4 (retrig enabled)
    if ch.vibratoWaveform < 4 then
        ch.vibratoPos = 0; ch.vibratoNeg = 0
    end
    if ch.tremoloWaveform < 4 then
        ch.tremoloPos = 0; ch.tremoloNeg = 0
    end

    -- Seek to sample offset if requested (effect 9)
    -- Guard: offset must be within sample bounds (spec §5.10)
    if seekBytes > 0 and seekBytes < sample.length then
        pcall(function() ch.source:seek(seekBytes / 8363) end)
    end

    ch.source:play()
    applyPan(ch.source, ch.pan)
end

-- ───────────────────────────────────────────────────────────────
--  playNote  (tick 0 processing for one channel)
-- ───────────────────────────────────────────────────────────────
local function playNote(channel, note)
    local ch      = channels[channel]
    local effect  = note.effect
    local param   = note.effectParam
    local ex      = bit32.rshift(param, 4)   -- high nibble
    local ey      = bit32.band (param, 0x0F) -- low  nibble

    -- Remember this row's note so doEffects can continue it on in-between ticks
    ch.currentNote = note

    -- Porta-to-Note flag: don't restart the sample (effects 3 and 5)
    local isPorta = (effect == 0x3 or effect == 0x5)
    -- Delay-Note flag: don't play now (effect EDx)
    local isDelay = (effect == 0xE and ex == 0xD)

    -- ── Section 4.1: volume reset only when instrument number is present ──
    if note.sample > 0 and note.sample <= 31 then
        local sampleVol = mod.samples[note.sample].volume
        ch.volume = sampleVol
        if ch.source then ch.source:setVolume(sampleVol / 64) end
        ch.lastSample = note.sample
    end

    -- ── Porta target / speed update (effect 3) ──
    if isPorta then
        if note.period > 0 then ch.portaTarget = note.period end
        if effect == 0x3 and param ~= 0 then ch.portaSpeed = param end
        -- Effect 5 param = vol-slide amounts (handled below)
    end

    -- ── Trigger sample / set period ──
    if note.period > 0 and not isPorta and not isDelay then
        local seekBytes = 0
        if effect == 0x9 then seekBytes = param * 0x100 end
        triggerSample(channel, note, seekBytes)
    elseif note.period > 0 and isDelay then
        -- Store for later playback at tick EDy
        ch.delayNote = note
        ch.delayTick = ey
    end

    -- ───────────────────────────────────────────────────────────
    --  Tick-0 effects
    -- ───────────────────────────────────────────────────────────
    if effect == 0x0 then
        -- 0xy Arpeggio: store semitone amounts (executed on ticks > 0)
        if param ~= 0 then ch.arpX = ex; ch.arpY = ey end

    elseif effect == 0x1 then
        -- 1xy Porta Up: remember speed (slide happens on ticks > 0)
        if param ~= 0 then ch.portaSpeed = param end

    elseif effect == 0x2 then
        -- 2xy Porta Down: remember speed
        if param ~= 0 then ch.portaSpeed = param end

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
        -- 8xy Pan: spec §5.9 – 00=left, 40=centre, 80=right
        -- Range 0..128 maps to -1..+1; values above 128 clamp to +1.
        local pan = math.max(-1.0, math.min(1.0, (param / 64.0) - 1.0))
        ch.pan = pan
        if ch.source then applyPan(ch.source, pan) end

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
        local vol = math.min(param, 64)
        ch.volume = vol
        if ch.source then ch.source:setVolume(vol / 64) end

    elseif effect == 0xD then
        -- Dxy Pattern Break (decimal: x*10+y rows into next pattern)
        local row = ex * 10 + ey
        if row > 63 then row = 0 end
        breakToRow = row

    elseif effect == 0xF then
        -- Fxy Set Speed / BPM
        if param > 0 and param <= 31 then
            ticksPerRow = param
        elseif param >= 32 then
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
            -- E5x: Set Finetune for current sample
            local ft = val; if ft > 7 then ft = ft - 16 end
            if note.sample > 0 and note.sample <= 31 then
                mod.samples[note.sample].finetune = ft
            end

        elseif sub == 0x6 then
            -- E6x: Pattern Loop
            if val == 0 then
                loopRow[channel] = currentRow     -- mark loop start
            else
                if loopCount[channel] == 0 then
                    loopCount[channel] = val      -- set loop count
                else
                    loopCount[channel] = loopCount[channel] - 1
                end
                if loopCount[channel] > 0 then
                    -- jump back: set currentRow to (loopStart - 1) so the
                    -- normal +1 increment at the end of the row lands on loopStart
                    currentRow = math.max(0, (loopRow[channel] or 1) - 1)
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
            if ch.source then applyPan(ch.source, pan) end

        elseif sub == 0xA then
            -- EAx: Fine Volume Slide Up (tick 0 only)
            setChannelVolume(channel, ch.volume + val)

        elseif sub == 0xB then
            -- EBx: Fine Volume Slide Down (tick 0 only)
            setChannelVolume(channel, ch.volume - val)

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
        local ex     = bit32.rshift(param, 4)
        local ey     = bit32.band (param, 0x0F)

        -- ── 0xy Arpeggio ──────────────────────────────────────
        if effect == 0x0 and param ~= 0 then
            local phase = currentTick % 3
            local idx
            if phase == 0 then
                idx = ch.noteIdx                           -- base note
            elseif phase == 1 then
                idx = math.min(ch.noteIdx + ch.arpX, 60)  -- + x semitones
            else
                idx = math.min(ch.noteIdx + ch.arpY, 60)  -- + y semitones
            end
            setPitchDirect(channel, PERIOD_TABLE[ch.ftIdx][idx])

        -- ── 1xy Porta Up ──────────────────────────────────────
        elseif effect == 0x1 then
            if param ~= 0 then ch.portaSpeed = param end
            setChannelPeriod(channel, ch.period - ch.portaSpeed)

        -- ── 2xy Porta Down ────────────────────────────────────
        elseif effect == 0x2 then
            if param ~= 0 then ch.portaSpeed = param end
            setChannelPeriod(channel, ch.period + ch.portaSpeed)

        -- ── 3xy / 5xy Porta To Note (+ optional vol slide) ───
        elseif effect == 0x3 or effect == 0x5 then
            doPortamento(channel)
            if effect == 0x5 then doVolumeSlide(channel) end

        -- ── 4xy / 6xy Vibrato (+ optional vol slide) ─────────
        elseif effect == 0x4 or effect == 0x6 then
            if ex ~= 0 then ch.vibratoSpeed = ex end
            if ey ~= 0 then ch.vibratoDepth = ey end
            local delta, newPos, newNeg = oscillatorStep(
                ch.vibratoWaveform, ch.vibratoPos, ch.vibratoNeg,
                ch.vibratoSpeed, ch.vibratoDepth, 128)
            ch.vibratoPos = newPos; ch.vibratoNeg = newNeg
            setPitchDirect(channel, ch.period + delta)
            if effect == 0x6 then doVolumeSlide(channel) end

        -- ── 7xy Tremolo ───────────────────────────────────────
        elseif effect == 0x7 then
            if ex ~= 0 then ch.tremoloSpeed = ex end
            if ey ~= 0 then ch.tremoloDepth = ey end
            local delta, newPos, newNeg = oscillatorStep(
                ch.tremoloWaveform, ch.tremoloPos, ch.tremoloNeg,
                ch.tremoloSpeed, ch.tremoloDepth, 64)
            ch.tremoloPos = newPos; ch.tremoloNeg = newNeg
            -- Apply temporary volume (don't store; tremolo doesn't modify base vol)
            local effVol = math.max(0, math.min(64, ch.volume + delta))
            if ch.source then ch.source:setVolume(effVol / 64) end

        -- ── Axy Volume Slide ──────────────────────────────────
        elseif effect == 0xA then
            doVolumeSlide(channel)

        -- ── Extended effects ──────────────────────────────────
        elseif effect == 0xE then
            local sub = ex
            local val = ey

            if sub == 0x9 then
                -- E9x: Retrig Note every x ticks
                if val > 0 and currentTick % val == 0 then
                    if ch.source then
                        pcall(function() ch.source:seek(0) end)
                        ch.source:play()
                    end
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
                    if dn.period > 0 then
                        triggerSample(channel, dn, 0)
                    end
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
    for channel = 1, mod.numChannels do
        local note = mod.patterns[currentPattern]
            and mod.patterns[currentPattern][currentRow]
            and mod.patterns[currentPattern][currentRow][channel]
        if note then
            playNote(channel, note)
        end
    end
end

-- ───────────────────────────────────────────────────────────────
--  processMOD  – main tick/row driver
-- ───────────────────────────────────────────────────────────────
local function processMOD(dt)
    local tickRate = 2 * bpm / 5   -- ticks per second  (125 BPM → 50 ticks/sec)
    tickAccum = tickAccum + dt * tickRate

    while tickAccum >= 1 do
        tickAccum = tickAccum - 1
        currentTick = currentTick + 1

        if currentTick >= ticksPerRow then
            currentTick = 0

            if patDelay > 0 then
                -- Pattern Delay: hold current row, keep effects running
                patDelay = patDelay - 1
                -- (channels continue their in-between effects via doEffects below)
            else
                -- Apply any pending pattern jump (Bxy) or pattern break (Dxy)
                if jumpToOrder ~= nil then
                    currentPatternIndex = math.min(jumpToOrder + 1, mod.songLength)
                    currentPattern      = mod.patternTable[currentPatternIndex]
                    currentRow          = (breakToRow or 0) + 1  -- 1-based
                    jumpToOrder         = nil
                    breakToRow          = nil
                elseif breakToRow ~= nil then
                    currentPatternIndex = currentPatternIndex + 1
                    if currentPatternIndex > mod.songLength then currentPatternIndex = 1 end
                    currentPattern = mod.patternTable[currentPatternIndex]
                    currentRow     = breakToRow + 1   -- 0-based → 1-based
                    breakToRow     = nil
                else
                    -- Normal row advance
                    currentRow = currentRow + 1
                    if currentRow > 64 then
                        currentRow          = 1
                        currentPatternIndex = currentPatternIndex + 1
                        if currentPatternIndex > mod.songLength then
                            currentPatternIndex = 1
                        end
                        currentPattern = mod.patternTable[currentPatternIndex]
                    end
                end

                updateRow()  -- tick 0 processing (may set jumpToOrder / breakToRow)
            end
        else
            -- In-between ticks: run tick-based effects
            doEffects()
        end

        -- ── Accurate software-loop: advance per-channel frame counters ────────
        -- Each tick has an exact duration of 5/(2*bpm) seconds.  Multiplying by
        -- the pitch factor (428/period) and the base sample rate (8363 Hz) gives
        -- the exact number of source frames consumed this tick, independent of
        -- any pitch drift from vibrato or arpeggio (those oscillate around the
        -- base period so the error averages to zero over a cycle).
        --
        -- seek() formula: tell()/seek() on this LÖVE build operate in wall-clock
        -- (real) seconds, i.e.  position = frames / (pitch × 8363).  If your
        -- build uses source-data seconds instead, replace the seek call with:
        --   ch.source:seek(ch.sampleFramePos / 8363, "seconds")
        if USE_SOFTWARE_LOOP then
            local secondsPerTick = 5 / (2 * bpm)
            for ci = 1, mod.numChannels do
                local ch = channels[ci]
                if ch.source and ch.hasLoop and ch.source:isPlaying() and ch.period > 0 then
                    local pitch   = 428 / ch.period
                    local loopLen = ch.loopEndFrame - ch.loopStartFrame
                    ch.sampleFramePos = ch.sampleFramePos + secondsPerTick * pitch * 8363
                    if loopLen > 0 and ch.sampleFramePos >= ch.loopEndFrame then
                        while ch.sampleFramePos >= ch.loopEndFrame do
                            ch.sampleFramePos = ch.sampleFramePos - loopLen
                        end
                        ch.source:seek(ch.sampleFramePos / (pitch * 8363), "seconds")
                    end
                end
            end
        end
    end

    -- LoveDOS fallback: coarse tell()-based loop check.
    -- Drifts at pitches other than C-2 (period 428) but costs almost nothing.
    -- Only active when USE_SOFTWARE_LOOP = false.
    if not USE_SOFTWARE_LOOP then
        for channel = 1, mod.numChannels do
            local ch = channels[channel]
            if ch.source and ch.hasLoop and ch.source:isPlaying() then
                local pos = ch.source:tell("seconds")
                if pos >= ch.loopEnd then
                    local overshoot = pos - ch.loopEnd
                    ch.source:seek(ch.loopStart + overshoot, "seconds")
                end
            end
        end
    end
end

-- tick driver: love.update
function love.update(dt)
    if not play then return end

    -- On the very first update after starting, trigger row if needed
    if currentTick >= ticksPerRow then
        currentTick = 0
        updateRow()
    end

    processMOD(dt)
end

local function periodToNote(period)
    local notes = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
    local octave = 0
    local foundNote = false

    for i, subTable in ipairs(PERIOD_TABLE) do
        for j, value in ipairs(subTable) do
            if period >= value then
                local noteIndex = (j - 1) % 12 + 1
                octave = math.floor((j - 1) / 12) + (i - 1)
                return notes[noteIndex] .. tostring(octave)
            end
        end
    end

    return nil
end

function love.draw()
    love.graphics.print("MOD Player", 10, 10)
    love.graphics.print("Pattern: " .. currentPattern, 10, 30)
    love.graphics.print("Row: " .. currentRow-1, 10, 50)
    love.graphics.print("Tick: " .. currentTick, 10, 70)
    
    -- Draw a simple visualization
    love.graphics.setColor(255, 255, 255)
    for i = 1, mod.numChannels do
        local volume = channels[i].source and channels[i].source.getVolume and channels[i].source:getVolume() or 0
        local height = volume * 100
        love.graphics.rectangle("fill", (i-1) * 30 + 10, 110, 20, height)

		local note = mod.patterns[currentPattern][currentRow][i]
		local noteStr = periodToNote(note.period)
		if noteStr == nil then
			noteStr = "---"
		end
		love.graphics.print(noteStr, (i-1) * 30 + 10, 90)
    end

	-- check for NON-LoveDOS
	if love.graphics.isActive and love.graphics.isActive() then
		-- Display pattern grid
		local gridX = 250
		local gridY = 25
		local cellWidth = 100
		local cellHeight = 20
		local visibleRows = 28  -- Number of rows to display at once

		for row = 0, visibleRows - 1 do
			local actualRow = (currentRow-1 + row) % 64
			local y = gridY + row * cellHeight

			-- Highlight current row
			if row == 0 then
				love.graphics.setColor(0.2, 0.2, 0.8, 0.5)
				love.graphics.rectangle("fill", gridX, y, cellWidth * mod.numChannels, cellHeight)
			end

			love.graphics.setColor(1, 1, 1)
			love.graphics.print(string.format("%02d", actualRow), gridX - 30, y)

			for channel = 1, mod.numChannels do
				local x = gridX + (channel - 1) * cellWidth
				love.graphics.rectangle("line", x, y, cellWidth, cellHeight)

				if mod.patterns[currentPattern] then
					local note = mod.patterns[currentPattern][actualRow+1][channel]
					local noteStr = periodToNote(note.period)

					local noteSample = ".."
					local noteEffect = "..."
					local noteEffectParam = ""

					
					if noteStr == nil then
						noteStr = "---"
					end
					
					if note.sample ~= nil and tonumber(note.sample) ~= 0 then
						if tonumber(note.sample) < 9 then
							noteSample = "0" .. note.sample
						else
							noteSample = string.format("%02X", note.sample )
						end
					end
					if tonumber(note.sample) == 0 then
						noteSample = ".."
					end

					if note.effect ~= nil and tonumber(note.effect) ~= 0 then
						noteEffect = string.format("%01X", note.effect )
					end
					if tonumber(note.effect) == 0 then
						noteEffect = "..."
					end
					if note.effectParam ~= nil and tonumber(note.effectParam) ~= 0 then
						noteEffectParam = string.format("%02X", note.effectParam )
					end
					if tonumber(note.effectParam) == 0 then
						noteEffectParam = ""
					end

					love.graphics.print(noteStr .. " " .. noteSample .. " " .. noteEffect .. noteEffectParam, x + 5, y + 2)
				end
			end
		end

		-- Display channel numbers
		for channel = 1, mod.numChannels do
			local x = gridX + (channel - 1) * cellWidth
			love.graphics.print(channel, x + cellWidth / 2 - 5, gridY - 20)
		end
	end
end

local function togglePlay()
    play = not play
    if not play then
        love.audio.stop()
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
	if key == "space" then
        togglePlay()
    end
end

-- LÖVE-DOS callback functions
function love.load()
	--love.window.setMode(1024, 768, {resizable = true, vsync = true})
    mod = loadMOD("MUSIC/space_debris.mod") -- Load your MOD file
    initializeChannels()
    loadSamples()
    -- Prime the player: set initial pattern and play row 1 immediately
    currentPatternIndex = 1
    currentPattern = mod.patternTable[currentPatternIndex]
    currentRow = 1
    currentTick = ticksPerRow  -- will fire on first update
end
