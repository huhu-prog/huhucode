-- inflate.lua
-- Pure Lua 5.4 raw DEFLATE inflater, adapted for Lua 5.1.
--
-- Supports:
--   - stored blocks
--   - fixed Huffman blocks
--   - dynamic Huffman blocks
--
-- Intended for ZIP method 8 entries.
-- ZIP stores raw DEFLATE streams, not zlib-wrapped streams.
--
-- Lua 5.1 adaptation: bitwise operators replaced with local bit functions.

local inflate = {}

----------------------------------------------------------------------
-- Lua 5.1 compatible 32-bit operations
----------------------------------------------------------------------
local bit = {}

function bit.lshift(x, n)
    return math.floor(x * 2 ^ n) % 0x100000000
end

function bit.rshift(x, n)
    return math.floor(x / 2 ^ n)
end

function bit.band(a, b)
    local r = 0
    local m = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            r = r + m
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        m = m * 2
    end
    return r
end

function bit.bor(a, b)
    local r = 0
    local m = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            r = r + m
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        m = m * 2
    end
    return r
end

function bit.bxor(a, b)
    local r = 0
    local m = 1
    while a > 0 or b > 0 do
        if (a % 2) ~= (b % 2) then
            r = r + m
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        m = m * 2
    end
    return r
end

local length_base = {
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17,
    19, 23, 27, 31,
    35, 43, 51, 59,
    67, 83, 99, 115,
    131, 163, 195, 227,
    258,
}

local length_extra = {
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1,
    2, 2, 2, 2,
    3, 3, 3, 3,
    4, 4, 4, 4,
    5, 5, 5, 5,
    0,
}

local dist_base = {
    1, 2, 3, 4,
    5, 7,
    9, 13,
    17, 25,
    33, 49,
    65, 97,
    129, 193,
    257, 385,
    513, 769,
    1025, 1537,
    2049, 3073,
    4097, 6145,
    8193, 12289,
    16385, 24577,
}

local dist_extra = {
    0, 0, 0, 0,
    1, 1,
    2, 2,
    3, 3,
    4, 4,
    5, 5,
    6, 6,
    7, 7,
    8, 8,
    9, 9,
    10, 10,
    11, 11,
    12, 12,
    13, 13,
}

local code_length_order = {
    16, 17, 18, 0, 8, 7, 9, 6,
    10, 5, 11, 4, 12, 3, 13, 2,
    14, 1, 15,
}

local BitStream = {}
BitStream.__index = BitStream

function BitStream:new(data)
    return setmetatable({
        data = data,
        pos = 1,
        bitbuf = 0,
        bitcount = 0,
    }, BitStream)
end

function BitStream:read_bits(n)
    while self.bitcount < n do
        local byte = self.data:byte(self.pos)

        if not byte then
            error("Unexpected end of DEFLATE stream", 0)
        end

        self.bitbuf = bit.bor(self.bitbuf, bit.lshift(byte, self.bitcount))
        self.bitcount = self.bitcount + 8
        self.pos = self.pos + 1
    end

    local mask = bit.lshift(1, n) - 1
    local value = bit.band(self.bitbuf, mask)

    self.bitbuf = bit.rshift(self.bitbuf, n)
    self.bitcount = self.bitcount - n

    return value
end

function BitStream:align_byte()
    self.bitbuf = 0
    self.bitcount = 0
end

function BitStream:read_u16()
    local b1 = self.data:byte(self.pos)
    local b2 = self.data:byte(self.pos + 1)

    if not b1 or not b2 then
        error("Unexpected end of DEFLATE stored block", 0)
    end

    self.pos = self.pos + 2

    return bit.bor(b1, bit.lshift(b2, 8))
end

function BitStream:read_bytes(n)
    local s = self.data:sub(self.pos, self.pos + n - 1)

    if #s ~= n then
        error("Unexpected end of DEFLATE byte data", 0)
    end

    self.pos = self.pos + n

    return s
end

local function build_huffman(lengths)
    local max_bits = 0
    local max_symbol = 0
    local bl_count = {}

    -- Count how many codes exist for each bit length.
    -- Also find the largest numeric symbol.
    for symbol, len in pairs(lengths) do
        if type(symbol) == "number" and symbol > max_symbol then
            max_symbol = symbol
        end

        if len and len > 0 then
            bl_count[len] = (bl_count[len] or 0) + 1

            if len > max_bits then
                max_bits = len
            end
        end
    end

    local code = 0
    local next_code = {}

    -- Generate the first canonical code for each bit length.
    for bits = 1, max_bits do
        code = bit.lshift(code + (bl_count[bits - 1] or 0), 1)
        next_code[bits] = code
    end

    local root = {}

    -- IMPORTANT:
    -- Canonical Huffman codes must be assigned in increasing symbol order.
    -- Do NOT use pairs() here because pairs() order is undefined.
    for symbol = 0, max_symbol do
        local len = lengths[symbol]

        if len and len > 0 then
            code = next_code[len]
            next_code[len] = code + 1

            local node = root

            -- Important correction:
            -- Decode tree must be built MSB-first for bit-by-bit decoding.
            --
            -- The previous version inserted bits LSB-first:
            --   for i = 0, len - 1 do
            --
            -- That produces an invalid tree for normal DEFLATE streams.
            for i = len - 1, 0, -1 do
                local bit_val = bit.band(bit.rshift(code, i), 1)

                node[bit_val] = node[bit_val] or {}
                node = node[bit_val]
            end

            node.symbol = symbol
        end
    end

    return root
end

local function decode_symbol(bs, tree)
    local node = tree

    while true do
        if node.symbol ~= nil then
            return node.symbol
        end

        local bit_val = bs:read_bits(1)
        node = node[bit_val]

        if not node then
            error("Invalid DEFLATE Huffman code", 0)
        end
    end
end

local fixed_lit_tree
local fixed_dist_tree

local function fixed_trees()
    if fixed_lit_tree and fixed_dist_tree then
        return fixed_lit_tree, fixed_dist_tree
    end

    local lit_lengths = {}

    for i = 0, 143 do
        lit_lengths[i] = 8
    end

    for i = 144, 255 do
        lit_lengths[i] = 9
    end

    for i = 256, 279 do
        lit_lengths[i] = 7
    end

    for i = 280, 287 do
        lit_lengths[i] = 8
    end

    local dist_lengths = {}

    for i = 0, 31 do
        dist_lengths[i] = 5
    end

    fixed_lit_tree = build_huffman(lit_lengths)
    fixed_dist_tree = build_huffman(dist_lengths)

    return fixed_lit_tree, fixed_dist_tree
end

local function dynamic_trees(bs)
    local hlit = bs:read_bits(5) + 257
    local hdist = bs:read_bits(5) + 1
    local hclen = bs:read_bits(4) + 4

    local code_lengths = {}

    for i = 1, hclen do
        code_lengths[code_length_order[i]] = bs:read_bits(3)
    end

    local code_length_tree = build_huffman(code_lengths)

    local lengths = {}

    while #lengths < hlit + hdist do
        local sym = decode_symbol(bs, code_length_tree)

        if sym <= 15 then
            lengths[#lengths + 1] = sym
        elseif sym == 16 then
            local repeat_count = bs:read_bits(2) + 3
            local previous = lengths[#lengths] or 0

            for _ = 1, repeat_count do
                lengths[#lengths + 1] = previous
            end
        elseif sym == 17 then
            local repeat_count = bs:read_bits(3) + 3

            for _ = 1, repeat_count do
                lengths[#lengths + 1] = 0
            end
        elseif sym == 18 then
            local repeat_count = bs:read_bits(7) + 11

            for _ = 1, repeat_count do
                lengths[#lengths + 1] = 0
            end
        else
            error("Invalid dynamic Huffman code length symbol", 0)
        end
    end

    local lit_lengths = {}
    local dist_lengths = {}

    for i = 0, hlit - 1 do
        lit_lengths[i] = lengths[i + 1] or 0
    end

    local any_dist = false

    for i = 0, hdist - 1 do
        local len = lengths[hlit + i + 1] or 0
        dist_lengths[i] = len

        if len > 0 then
            any_dist = true
        end
    end

    -- Some odd streams may have no distance tree if no distances are used.
    -- Give the decoder a harmless placeholder.
    if not any_dist then
        dist_lengths[0] = 1
    end

    return build_huffman(lit_lengths), build_huffman(dist_lengths)
end

local function inflate_codes(bs, lit_tree, dist_tree, out)
    while true do
        local sym = decode_symbol(bs, lit_tree)

        if sym < 256 then
            out[#out + 1] = string.char(sym)
        elseif sym == 256 then
            return
        elseif sym >= 257 and sym <= 285 then
            local index = sym - 257 + 1
            local length = length_base[index]
            local extra = length_extra[index]

            if extra and extra > 0 then
                length = length + bs:read_bits(extra)
            end

            local dist_sym = decode_symbol(bs, dist_tree)
            local distance = dist_base[dist_sym + 1]
            local dist_extra_bits = dist_extra[dist_sym + 1]

            if not distance then
                error("Invalid DEFLATE distance symbol", 0)
            end

            if dist_extra_bits and dist_extra_bits > 0 then
                distance = distance + bs:read_bits(dist_extra_bits)
            end

            for _ = 1, length do
                local source_index = #out - distance + 1

                if source_index < 1 then
                    error("Invalid DEFLATE back-reference distance", 0)
                end

                out[#out + 1] = out[source_index]
            end
        else
            error("Invalid DEFLATE literal/length symbol", 0)
        end
    end
end

function inflate.inflate(data)
    local bs = BitStream:new(data)
    local out = {}
    local final = false

    repeat
        final = bs:read_bits(1) == 1

        local block_type = bs:read_bits(2)

        if block_type == 0 then
            bs:align_byte()

            local len = bs:read_u16()
            local nlen = bs:read_u16()

            if bit.band(bit.bxor(len, nlen), 0xFFFF) ~= 0xFFFF then
                error("Invalid DEFLATE stored block length check", 0)
            end

            local bytes = bs:read_bytes(len)

            for i = 1, #bytes do
                out[#out + 1] = bytes:sub(i, i)
            end
        elseif block_type == 1 then
            local lit_tree, dist_tree = fixed_trees()
            inflate_codes(bs, lit_tree, dist_tree, out)
        elseif block_type == 2 then
            local lit_tree, dist_tree = dynamic_trees(bs)
            inflate_codes(bs, lit_tree, dist_tree, out)
        else
            error("Reserved DEFLATE block type encountered", 0)
        end
    until final

    return table.concat(out)
end

return inflate
