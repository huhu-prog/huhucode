-- reader/zipreader.lua
-- Minimal pure Lua ZIP reader, adapted for Lua 5.1.
-- Supports central directory reading, stored entries, and DEFLATE entries

local inflate = require("reader.inflate")

local zip = {}
zip.__index = zip

-- Lua 5.1 compatible unsigned 16-bit little-endian read
local function u16(s, pos)
    local b1, b2 = s:byte(pos, pos + 1)
    return b1 + b2 * 256
end

-- Lua 5.1 compatible unsigned 32-bit little-endian read
local function u32(s, pos)
    local b1, b2, b3, b4 = s:byte(pos, pos + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

---------------------------------------------------------------------------
-- Helper: encode a string as uppercase hex (used for UTF-8 path fallback)
---------------------------------------------------------------------------
local function hex_encode(s)
    local t = {}
    for i = 1, #s do
        t[#t + 1] = string.format("%02X", string.byte(s, i))
    end
    return table.concat(t)
end

---------------------------------------------------------------------------
-- read_all(path) – read the full content of a file
--
-- Lua 5.1 on Windows uses ANSI fopen(), so UTF-8 encoded .lua source files
-- can produce "Illegal byte sequence" when the path contains non-ASCII
-- characters (e.g. Chinese).  When that happens we fall back to PowerShell
-- which natively understands Unicode paths.
---------------------------------------------------------------------------
local function read_all(path)
    local f, err = io.open(path, "rb")
    if f then
        local data = f:read("*a")
        f:close()
        return data
    end

    -- Only try the encoding fallback for the typical UTF-8-vs-ANSI symptom
    if not err or not err:find("Illegal byte sequence") then
        return nil, err
    end

    -- Fallback: encode the UTF-8 path as hex, then use PowerShell to
    -- copy the file to a temp path with an ASCII-only name.
    -- The hex string is pure ASCII so os.execute() passes it through
    -- system() without corruption.
    local hex = hex_encode(path)
    local tmp = os.tmpname()

    local ps_cmd = [[powershell -NoProfile -Command "$h=']]
        .. hex
        .. [[';$b=(0..($h.Length/2-1)|ForEach-Object{[convert]::ToInt32($h.Substring($_*2,2),16)});$p=[System.Text.Encoding]::UTF8.GetString($b);Copy-Item -LiteralPath $p -Destination ']]
        .. tmp
        .. [[' -Force"]]

    os.execute(ps_cmd)

    f, err = io.open(tmp, "rb")
    if not f then
        os.remove(tmp)
        return nil, "UTF-8 path fallback failed: " .. (err or "unknown")
    end

    local data = f:read("*a")
    f:close()
    os.remove(tmp)
    return data
end

local function find_eocd(data)
    -- EOCD can have up to 65535 bytes comment. Search backwards near EOF.
    local min_pos = math.max(1, #data - 65535 - 22)
    for pos = #data - 21, min_pos, -1 do
        if data:sub(pos, pos + 3) == "PK\005\006" then
            return pos
        end
    end
    return nil, "End of central directory not found"
end

function zip.open(path)
    local data, err = read_all(path)
    if not data then return nil, err end

    local eocd_pos, eocd_err = find_eocd(data)
    if not eocd_pos then return nil, eocd_err end

    local disk_no = u16(data, eocd_pos + 4)
    local cd_disk = u16(data, eocd_pos + 6)
    local entries_disk = u16(data, eocd_pos + 8)
    local entries_total = u16(data, eocd_pos + 10)
    local cd_size = u32(data, eocd_pos + 12)
    local cd_offset = u32(data, eocd_pos + 16)

    if disk_no ~= 0 or cd_disk ~= 0 then
        return nil, "Multi-disk ZIP files are not supported"
    end

    if entries_disk ~= entries_total then
        return nil, "Multi-disk ZIP entry count mismatch"
    end

    local self = setmetatable({
        path = path,
        data = data,
        entries = {},
        order = {},
        cd_size = cd_size,
        cd_offset = cd_offset,
    }, zip)

    local pos = cd_offset + 1

    for _ = 1, entries_total do
        if data:sub(pos, pos + 3) ~= "PK\001\002" then
            return nil, "Bad central directory signature at byte " .. tostring(pos)
        end

        local flags = u16(data, pos + 8)
        local method = u16(data, pos + 10)
        local crc32 = u32(data, pos + 16)
        local compressed_size = u32(data, pos + 20)
        local uncompressed_size = u32(data, pos + 24)
        local name_len = u16(data, pos + 28)
        local extra_len = u16(data, pos + 30)
        local comment_len = u16(data, pos + 32)
        local local_header_offset = u32(data, pos + 42)

        local name_start = pos + 46
        local name = data:sub(name_start, name_start + name_len - 1)

        local entry = {
            name = name,
            flags = flags,
            method = method,
            crc32 = crc32,
            compressed_size = compressed_size,
            uncompressed_size = uncompressed_size,
            local_header_offset = local_header_offset,
        }

        self.entries[name] = entry
        self.order[#self.order + 1] = name

        pos = name_start + name_len + extra_len + comment_len
    end

    return self
end

function zip:list()
    local out = {}
    for i, name in ipairs(self.order) do
        out[i] = name
    end
    return out
end

function zip:has(name)
    return self.entries[name] ~= nil
end

function zip:read(name)
    local entry = self.entries[name]
    if not entry then
        return nil, "ZIP entry not found: " .. tostring(name)
    end

    local data = self.data
    local pos = entry.local_header_offset + 1

    if data:sub(pos, pos + 3) ~= "PK\003\004" then
        return nil, "Bad local file header signature for: " .. name
    end

    local name_len = u16(data, pos + 26)
    local extra_len = u16(data, pos + 28)
    local data_start = pos + 30 + name_len + extra_len

    local compressed_data =
        data:sub(data_start, data_start + entry.compressed_size - 1)

    if entry.method == 0 then
        return compressed_data
    end

    if entry.method == 8 then
        local ok, result = pcall(inflate.inflate, compressed_data)

        if not ok then
            return nil, "Failed to inflate ZIP entry '" .. name .. "': " .. tostring(result)
        end

        if #result ~= entry.uncompressed_size then
            return nil,
                ("Inflated ZIP entry '%s' has size %d, expected %d")
                :format(name, #result, entry.uncompressed_size)
        end

        return result
    end

    return nil,
        ("ZIP entry '%s' uses unsupported compression method %d. Supported methods: 0/store, 8/deflate.")
        :format(name, entry.method)
end

return zip
