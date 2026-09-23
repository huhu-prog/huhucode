-- xmlmini.lua
-- Tiny XML helpers for XLSX/OpenXML parsing.
-- Not a full XML parser. Good enough for SpreadsheetML parts in this experiment.

---@class XmlMini
local xml = {}

local entities = {
    amp = "&",
    lt = "<",
    gt = ">",
    quot = '"',
    apos = "'",
}

--- Decode basic XML entities.
---
---@param s string?
---@return string
function xml.decode_entities(s)
    if not s then
        return ""
    end

    s = s:gsub("&#x([%da-fA-F]+);", function(hex)
        local n = tonumber(hex, 16)

        if utf8 and utf8.char then
            return utf8.char(n)
        end

        return ""
    end)

    s = s:gsub("&#(%d+);", function(dec)
        local n = tonumber(dec, 10)

        if utf8 and utf8.char then
            return utf8.char(n)
        end

        return ""
    end)

    s = s:gsub("&([%a]+);", function(name)
        return entities[name] or ("&" .. name .. ";")
    end)

    return s
end

--- Parse attributes from an XML tag string.
---
---@param tag string
---@return table<string, string>
function xml.attrs(tag)
    local out = {}

    for key, quote, value in tag:gmatch("([%w_:.-]+)%s*=%s*(['\"])(.-)%2") do
        out[key] = xml.decode_entities(value)
    end

    return out
end

--- Get decoded text between two Lua patterns.
---
---@param s string
---@param open_pat string
---@param close_pat string
---@return string
function xml.text_between(s, open_pat, close_pat)
    local content = s:match(open_pat .. "(.-)" .. close_pat)

    return xml.decode_entities(content or "")
end

--- Remove XML namespace prefix from a name.
---
---@param name string
---@return string
function xml.strip_ns(name)
    return (name:gsub("^.-:", ""))
end

--- Collect all <t>...</t> text from a rich text/shared string block.
---
--- Rich-text cells store content as <r><rPr>...</rPr><t>text</t></r>.
--- The <rPr> block contains formatting tags (<rFont>, <charset>,
--- <vertAlign>) whose names happen to end with "t".  If NOT stripped
--- first, the gmatch below will treat them as <t> tags, leaking XML
--- fragments like "</rPr><t xml:space=\"preserve\">" into the output.
---
---@param block string
---@return string
function xml.get_t_text(block)
    local pieces = {}

    -- Strip <rPr/> (self-closing) and <rPr>...</rPr> (with content).
    -- Once <rPr> is gone, every remaining *t tag is a genuine <t>
    -- element (or namespace-prefixed <x:t>).
    local cleaned = block
        :gsub("<rPr[^>]*/>", "")
        :gsub("<rPr[^>]*>.-</rPr>", "")

    for text in cleaned:gmatch("<[%w_]*:?t[^>]*>(.-)</[%w_]*:?t>") do
        pieces[#pieces + 1] = xml.decode_entities(text)
    end

    return table.concat(pieces)
end

--- Iterate over simple XML tag blocks.
---
---@param s string
---@param tag string
---@return function
function xml.each_tag_block(s, tag)
    local pattern = "<" .. tag .. "([^>]*)>(.-)</" .. tag .. ">"

    return s:gmatch(pattern)
end

return xml
