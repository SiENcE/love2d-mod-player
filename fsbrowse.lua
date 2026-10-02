-- fsbrowse.lua — minimal access to the real filesystem for the song browser.
--
-- love.filesystem is sandboxed to the game and save folders, so folders are
-- listed natively: Win32 FindFirstFileW via FFI on Windows (Unicode paths,
-- drive list), `ls` elsewhere.  Paths are UTF-8 strings.

local ffi = require("ffi")

local fsb = {}
fsb.isWindows = ffi.os == "Windows"
fsb.sep = fsb.isWindows and "\\" or "/"

local function lower(s) return s:lower() end
local function byName(a, b) return lower(a) < lower(b) end

-- ── Path helpers ─────────────────────────────────────────────────────────────

function fsb.normalize(path)
    if fsb.isWindows then
        path = path:gsub("/", "\\")
        if path:match("^%a:$") then path = path .. "\\" end
        if #path > 3 then path = path:gsub("\\+$", "") end
    elseif #path > 1 then
        path = path:gsub("/+$", "")
    end
    return path
end

function fsb.join(dir, name)
    if dir:sub(-1) == fsb.sep then return dir .. name end
    return dir .. fsb.sep .. name
end

-- Parent folder, or nil at a root (on Windows the caller shows the drives).
function fsb.parent(dir)
    dir = fsb.normalize(dir)
    if fsb.isWindows then
        if dir:match("^%a:\\$") then return nil end
        local p = dir:match("^(.*)\\[^\\]+$")
        if p and p:match("^%a:$") then p = p .. "\\" end
        return p
    end
    if dir == "/" then return nil end
    return dir:match("^(.*)/[^/]+$") or "/"
end

function fsb.basename(path)
    return path:match("[^\\/]+$") or path
end

-- ── Windows ──────────────────────────────────────────────────────────────────
if fsb.isWindows then
    ffi.cdef[[
        typedef struct {
            uint32_t dwFileAttributes;
            uint32_t ftCreationTime[2], ftLastAccessTime[2], ftLastWriteTime[2];
            uint32_t nFileSizeHigh, nFileSizeLow;
            uint32_t dwReserved0, dwReserved1;
            uint16_t cFileName[260];
            uint16_t cAlternateFileName[14];
        } fsb_find_data_w;
        void* FindFirstFileW(const uint16_t* name, fsb_find_data_w* data);
        int   FindNextFileW(void* handle, fsb_find_data_w* data);
        int   FindClose(void* handle);
        uint32_t GetLogicalDrives(void);
        int MultiByteToWideChar(uint32_t cp, uint32_t flags, const char* s, int n, uint16_t* w, int wn);
        int WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t* w, int wn, char* s, int n,
                                const char* def, int* used);
        void* CreateFileW(const uint16_t* name, uint32_t access, uint32_t share, void* sa,
                          uint32_t disposition, uint32_t flags, void* tmpl);
        int   GetFileSizeEx(void* handle, int64_t* size);
        int   ReadFile(void* handle, void* buf, uint32_t n, uint32_t* read, void* overlapped);
        int   CloseHandle(void* handle);
    ]]
    local C = ffi.C
    local CP_UTF8 = 65001
    local INVALID = ffi.cast("void*", -1)

    local function wide(s)
        local n = C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
        local w = ffi.new("uint16_t[?]", n)
        C.MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n)
        return w
    end

    local function utf8(w)
        local n = C.WideCharToMultiByte(CP_UTF8, 0, w, -1, nil, 0, nil, nil)
        local s = ffi.new("char[?]", n)
        C.WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, nil, nil)
        return ffi.string(s)
    end

    function fsb.drives()
        local mask, out = C.GetLogicalDrives(), {}
        for i = 0, 25 do
            if bit.band(mask, bit.lshift(1, i)) ~= 0 then
                out[#out + 1] = string.char(65 + i) .. ":\\"
            end
        end
        return out
    end

    -- Sorted sub-folders and files of `dir` (hidden/system entries skipped).
    function fsb.list(dir)
        local data = ffi.new("fsb_find_data_w")
        local h = C.FindFirstFileW(wide(fsb.join(dir, "*")), data)
        if h == INVALID then return nil, "cannot open folder" end
        local dirs, files = {}, {}
        repeat
            local name = utf8(data.cFileName)
            local attr = data.dwFileAttributes
            if name ~= "." and name ~= ".." and bit.band(attr, 0x6) == 0 then
                if bit.band(attr, 0x10) ~= 0 then dirs[#dirs + 1] = name
                else files[#files + 1] = name end
            end
        until C.FindNextFileW(h, data) == 0
        C.FindClose(h)
        table.sort(dirs, byName)
        table.sort(files, byName)
        return dirs, files
    end

    function fsb.read(path)
        local h = C.CreateFileW(wide(path), 0x80000000, 1, nil, 3, 0x80, nil) -- GENERIC_READ, OPEN_EXISTING
        if h == INVALID then return nil, "cannot open " .. path end
        local size = ffi.new("int64_t[1]")
        C.GetFileSizeEx(h, size)
        local n = tonumber(size[0])
        if n > 16 * 1024 * 1024 then C.CloseHandle(h); return nil, "file too large" end
        local buf, got = ffi.new("uint8_t[?]", math.max(n, 1)), ffi.new("uint32_t[1]")
        local ok = C.ReadFile(h, buf, n, got, nil)
        C.CloseHandle(h)
        if ok == 0 then return nil, "cannot read " .. path end
        return ffi.string(buf, got[0])
    end

-- ── POSIX ────────────────────────────────────────────────────────────────────
else
    local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

    function fsb.drives() return { "/" } end

    function fsb.list(dir)
        local p = io.popen("ls -1Ap -- " .. quote(dir) .. " 2>/dev/null")
        if not p then return nil, "cannot open folder" end
        local dirs, files = {}, {}
        for line in p:lines() do
            if line:sub(1, 1) ~= "." then
                if line:sub(-1) == "/" then dirs[#dirs + 1] = line:sub(1, -2)
                else files[#files + 1] = line end
            end
        end
        p:close()
        table.sort(dirs, byName)
        table.sort(files, byName)
        return dirs, files
    end

    function fsb.read(path)
        local f, err = io.open(path, "rb")
        if not f then return nil, err end
        local d = f:read("*a")
        f:close()
        return d
    end
end

-- Folder the game runs from (the source folder, or the .exe's folder if fused).
function fsb.gameFolder()
    local base = love.filesystem.isFused() and love.filesystem.getSourceBaseDirectory()
                 or love.filesystem.getSource()
    return fsb.normalize(base)
end

return fsb
