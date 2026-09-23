-- xlsxreader.lua
-- Minimal XLSX reader built on reader/zipreader.lua + reader/xmlmini.lua.
-- Adapted for WMS Basis Lua 5.1 environment.

--
-- Current scope:
--   - Reads normal Excel XLSX files using ZIP method 8/DEFLATE
--   - Reads stored/uncompressed XLSX ZIP entries
--   - Reads workbook sheet list
--   - Reads sharedStrings.xml
--   - Reads worksheet rows/cells
--   - Supports shared strings, inline strings, booleans, errors, and raw numeric text
--   - Fills missing blank cells so rows are rectangular
--   - Supports header-mapped rows
--   - Includes basic Excel date serial helper
--
-- Notes:
--   - This is not a full XLSX implementation yet.
--   - Values are returned as strings by default to avoid damaging IDs/serials.
--   - Optional conversions are available through rows() options.

local zip = require("reader.zipreader")
local xml = require("reader.xmlmini")

---@class XlsxReadOptions
---@field header boolean? If true, use first row as object keys.
---@field width integer? Optional forced row width.
---@field convert_numbers boolean? Convert numeric-looking cells to numbers.
---@field convert_booleans boolean? Convert boolean cells to true/false.
---@field trim_headers boolean? Trim header names when mapping objects.
---@field skip_empty_rows boolean? Skip fully empty rows.

---@class XlsxSheet
---@field name string
---@field sheetId string?
---@field rid string?
---@field path string

---@class XlsxWorkbook
---@field path string
---@field archive table
---@field sheets XlsxSheet[]
---@field shared_strings string[]
---@field list_sheets fun(self: XlsxWorkbook): string[]
---@field sheet_names fun(self: XlsxWorkbook): string[]
---@field first_sheet fun(self: XlsxWorkbook): XlsxSheet?
---@field sheet fun(self: XlsxWorkbook, index_or_name: integer|string): XlsxSheet?
---@field rows fun(self: XlsxWorkbook, index_or_name: integer|string?, options: XlsxReadOptions?): table[]?, string?
---@field rows_as_objects fun(self: XlsxWorkbook, index_or_name: integer|string?, options: XlsxReadOptions?): table[]?, string?

local xlsx = {}
xlsx.__index = xlsx

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------

---@param s string
---@return string
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param col string
---@return integer
local function col_to_number(col)
    local n = 0

    col = col:upper()

    for i = 1, #col do
        local b = col:byte(i)
        n = n * 26 + (b - 64)
    end

    return n
end

---@param ref string?
---@return integer?, integer?
local function cell_ref_to_row_col(ref)
    if not ref then
        return nil, nil
    end

    local col, row = ref:match("^([A-Za-z]+)(%d+)$")

    if not col then
        return nil, nil
    end

    return tonumber(row), col_to_number(col)
end

---@param row table
---@param width integer
---@return boolean
local function row_is_empty(row, width)
    for c = 1, width do
        if row[c] ~= nil and row[c] ~= "" then
            return false
        end
    end

    return true
end

-------------------------------------------------------------------------------
-- Excel date helpers
-------------------------------------------------------------------------------

--- Convert an Excel serial date number to Y/M/D.
--- Uses the Windows 1900 date system by default.
---
--- Excel incorrectly treats 1900 as a leap year for Lotus compatibility.
--- This function accounts for that by subtracting one day after serial 59.
---
---@param serial number
---@param date_1904 boolean?
---@return integer year
---@return integer month
---@return integer day
function xlsx.excel_date_to_ymd(serial, date_1904)
    local base_year
    local base_month
    local base_day

    if date_1904 then
        base_year, base_month, base_day = 1904, 1, 1
    else
        base_year, base_month, base_day = 1899, 12, 31

        if serial >= 60 then
            serial = serial - 1
        end
    end

    local days = math.floor(serial)

    local function is_leap(year)
        return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    end

    local month_days = {
        31, 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31,
    }

    local y, m, d = base_year, base_month, base_day

    while days > 0 do
        d = d + 1

        month_days[2] = is_leap(y) and 29 or 28

        if d > month_days[m] then
            d = 1
            m = m + 1

            if m > 12 then
                m = 1
                y = y + 1
            end
        end

        days = days - 1
    end

    return y, m, d
end

--- Convert an Excel serial date number to YYYY-MM-DD.
---
---@param serial number|string
---@param date_1904 boolean?
---@return string
function xlsx.excel_date_to_iso(serial, date_1904)
    local serial_number = tonumber(serial)

    if not serial_number then
        return ""
    end

    local y, m, d = xlsx.excel_date_to_ymd(serial_number, date_1904)

    return ("%04d-%02d-%02d"):format(y, m, d)
end

-------------------------------------------------------------------------------
-- XLSX relationship path helpers
-------------------------------------------------------------------------------

---@param base string
---@param target string?
---@return string?
local function norm_path(base, target)
    if not target then
        return nil
    end

    -- Absolute package path.
    if target:sub(1, 1) == "/" then
        return target:sub(2)
    end

    -- Relationship files live in _rels folders and point relative to the
    -- owning part, not relative to the .rels file itself.
    --
    -- Example:
    --   base:   xl/_rels/workbook.xml.rels
    --   owner:  xl/workbook.xml
    --   target: worksheets/sheet1.xml
    --   result: xl/worksheets/sheet1.xml
    local owner = base

    owner = owner:gsub("/_rels/([^/]+)%.rels$", "/%1")
    owner = owner:gsub("^_rels/([^/]+)%.rels$", "%1")

    local prefix = owner:match("^(.*[/\\])") or ""
    local combined = prefix .. target

    combined = combined:gsub("/%./", "/")

    while combined:find("[^/]+/%.%./") do
        combined = combined:gsub("[^/]+/%.%./", "", 1)
    end

    return combined
end

---@param rels_xml string?
---@param base string
---@return table<string, string>
local function parse_relationships(rels_xml, base)
    local rels = {}

    if not rels_xml then
        return rels
    end

    for tag in rels_xml:gmatch("<Relationship%s+([^>]*)/>") do
        local a = xml.attrs(tag)

        if a.Id and a.Target then
            rels[a.Id] = norm_path(base or "", a.Target)
        end
    end

    return rels
end

---@param workbook_xml string
---@param rels table<string, string>
---@return XlsxSheet[]
local function parse_workbook_sheets(workbook_xml, rels)
    local sheets = {}

    if not workbook_xml then
        return sheets
    end

    for tag in workbook_xml:gmatch("<sheet%s+([^>]*)/>") do
        local a = xml.attrs(tag)
        local rid = a["r:id"] or a.id
        local target = rid and rels[rid]

        sheets[#sheets + 1] = {
            name = a.name or ("Sheet" .. tostring(#sheets + 1)),
            sheetId = a.sheetId,
            rid = rid,
            path = target or ("xl/worksheets/sheet" .. tostring(#sheets + 1) .. ".xml"),
        }
    end

    return sheets
end

---@param shared_xml string?
---@return string[]
local function parse_shared_strings(shared_xml)
    local strings = {}

    if not shared_xml then
        return strings
    end

    for block in shared_xml:gmatch("<si[^>]*>(.-)</si>") do
        strings[#strings + 1] = xml.get_t_text(block)
    end

    return strings
end

-------------------------------------------------------------------------------
-- Cell parsing
-------------------------------------------------------------------------------

---@param value string
---@return boolean
local function is_number_text(value)
    return value:match("^[+-]?%d+$") ~= nil or
        value:match("^[+-]?%d+%.%d+$") ~= nil
end

---@param cell_xml string
---@param attrs table<string, string>
---@param shared_strings string[]
---@param options XlsxReadOptions
---@return any
local function cell_value(cell_xml, attrs, shared_strings, options)
    local t = attrs.t

    if t == "inlineStr" then
        return xml.get_t_text(cell_xml)
    end

    local v = cell_xml:match("<v[^>]*>(.-)</v>")

    if not v then
        return ""
    end

    v = xml.decode_entities(v)

    if t == "s" then
        local idx = tonumber(v)

        if idx then
            return shared_strings[idx + 1] or ""
        end

        return ""
    elseif t == "b" then
        if options.convert_booleans then
            return v == "1"
        end

        return v == "1" and "TRUE" or "FALSE"
    elseif t == "e" then
        return v
    else
        -- Numbers, dates-as-numbers, formulas cached values, and raw values.
        if options.convert_numbers and is_number_text(v) then
            return tonumber(v)
        end

        return v
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Open an XLSX workbook.
---
---@param path string
---@return XlsxWorkbook?
---@return string?
function xlsx.open(path)
    local archive, err = zip.open(path)

    if not archive then
        return nil, err
    end

    local workbook_xml, workbook_err = archive:read("xl/workbook.xml")

    if not workbook_xml then
        return nil, workbook_err or "xl/workbook.xml not found"
    end

    local rels_xml, rels_err = archive:read("xl/_rels/workbook.xml.rels")

    if not rels_xml then
        return nil, rels_err or "xl/_rels/workbook.xml.rels not found"
    end

    local rels = parse_relationships(rels_xml, "xl/_rels/workbook.xml.rels")
    local sheets = parse_workbook_sheets(workbook_xml, rels)

    local shared_xml = archive:read("xl/sharedStrings.xml")

    -- sharedStrings.xml is common but not mandatory.
    -- Some XLSX files use inline strings instead.
    if not shared_xml then
        shared_xml = ""
    end

    local shared_strings = parse_shared_strings(shared_xml)

    local workbook = setmetatable({
        path = path,
        archive = archive,
        sheets = sheets,
        shared_strings = shared_strings,
    }, xlsx)

    ---@cast workbook XlsxWorkbook
    return workbook, nil
end

--- Return sheet names.
---
---@return string[]
function xlsx:list_sheets()
    local out = {}

    for i, sheet in ipairs(self.sheets) do
        out[i] = sheet.name
    end

    return out
end

--- Alias for list_sheets().
---
---@return string[]
function xlsx:sheet_names()
    return self:list_sheets()
end

--- Return the first sheet object.
---
---@return XlsxSheet?
function xlsx:first_sheet()
    return self.sheets[1]
end

--- Return a sheet by 1-based index or name.
---
---@param index_or_name integer|string
---@return XlsxSheet?
function xlsx:sheet(index_or_name)
    if type(index_or_name) == "number" then
        return self.sheets[index_or_name]
    end

    for _, sheet in ipairs(self.sheets) do
        if sheet.name == index_or_name then
            return sheet
        end
    end
end

--- Read rows from a sheet.
---
--- Examples:
---   book:rows(1)
---   book:rows("cleaned_assets")
---   book:rows(1, { header = true })
---
---@param index_or_name integer|string?
---@param options XlsxReadOptions?
---@return table[]?
---@return string?
function xlsx:rows(index_or_name, options)
    options = options or {}

    local sheet = self:sheet(index_or_name or 1)

    if not sheet then
        return nil, "Sheet not found: " .. tostring(index_or_name)
    end

    local sheet_xml, err = self.archive:read(sheet.path)

    if not sheet_xml then
        return nil, err or ("Worksheet XML not found: " .. tostring(sheet.path))
    end

    local rows = {}
    local max_col = 0

    for row_attrs_str, row_xml in sheet_xml:gmatch("<row%s*([^>]*)>(.-)</row>") do
        local row_attrs = xml.attrs(row_attrs_str)
        local row_index = tonumber(row_attrs.r) or (#rows + 1)
        local row = {}

        -- Normalize self-closing cells (<c .../>) into explicit open/close
        -- pairs so the pattern below never swallows the "/" as an attribute
        -- character and spans multiple cells.
        row_xml = row_xml:gsub("<c([^>]*)/>", "<c%1></c>")

        -- Cells with explicit closing tags.
        for cell_attrs_str, cell_xml in row_xml:gmatch("<c%s*([^>]*)>(.-)</c>") do
            local attrs = xml.attrs(cell_attrs_str)
            local _, col = cell_ref_to_row_col(attrs.r)

            col = col or (#row + 1)

            row[col] = cell_value(cell_xml, attrs, self.shared_strings, options)

            if col > max_col then
                max_col = col
            end
        end

        rows[row_index] = row
    end

    local width = options.width or max_col

    -- Fill missing blank cells so rows are rectangular.
    for _, row in pairs(rows) do
        for c = 1, width do
            if row[c] == nil then
                row[c] = ""
            end
        end
    end

    if options.skip_empty_rows then
        local compacted = {}

        for _, row in ipairs(rows) do
            if not row_is_empty(row, width) then
                compacted[#compacted + 1] = row
            end
        end

        rows = compacted
    end

    if options.header then
        local header = rows[1] or {}
        local mapped = {}

        for r = 2, #rows do
            local source = rows[r]

            if source then
                local obj = {}

                for c = 1, width do
                    local name = header[c]

                    if name and name ~= "" then
                        if options.trim_headers then
                            name = trim(name)
                        end

                        obj[name] = source[c] or ""
                    end
                end

                mapped[#mapped + 1] = obj
            end
        end

        return mapped
    end

    return rows
end

--- Convenience wrapper for rows(index_or_name, { header = true }).
---
---@param index_or_name integer|string?
---@param options XlsxReadOptions?
---@return table[]?
---@return string?
function xlsx:rows_as_objects(index_or_name, options)
    options = options or {}
    options.header = true

    return self:rows(index_or_name, options)
end

return xlsx
