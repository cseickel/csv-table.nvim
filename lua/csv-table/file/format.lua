--[[
Defines `csv.Format`, one per column: its kind, the decimals to print, and the
width, alignment and printf spec the user has asked for.

A CSV cell is text, so a sample of rows is the only thing that says what a column
holds.
]]

local M = {}

---@class csv.Format
---@field kind "int"|"float"|"date"|"text"
---@field precision integer Decimals to print. Zero unless `kind` is "float".
---@field width integer|nil Characters every value is padded to. Absent until the user asks for padding.
---@field align "left"|"center"|"right"|nil Which side the padding goes. Absent alongside `width`.
---@field spec string|nil A printf specification, replacing every other rule.

local MAX_PRECISION = 6

-- A column printed from float32 has noise past seven digits: a price of 199.59
-- reaches the file as 199.589996338, which reads as nine decimals.
local SIGNIFICANT_DIGITS = 7

---@return csv.Format
function M.plain()
  return { kind = "text", precision = 0 }
end

--- Decimals a value needs once its float noise is gone, or nil when the value is
--- not a number.
---@param value string
---@return integer|nil
function M.decimals(value)
  local number = tonumber(value)
  if not number then
    return nil
  end

  -- Round-tripping through %g drops the noise digits, and reprinting in fixed
  -- notation keeps the count right for values %g would render as `1e-05`.
  local rounded = tonumber(string.format("%." .. SIGNIFICANT_DIGITS .. "g", number))
  local fraction = string.format("%.10f", rounded):match("^%-?%d+%.(%d+)$")
  if not fraction then
    return 0
  end
  return #(fraction:gsub("0+$", ""))
end

--- What follows the opening shape of a date, which is any mixture of the
--- characters a date, a time, an offset and a separator between them are drawn
--- from. Anchored at both ends like `tonumber`, so `2024-01-15 not a date` is
--- text rather than a date with prose after it that the coloring would cover.
local DATE_BODY = "[-%d:%./T Z+]*$"

--- The shapes a date column's values take: an ISO date, a slashed date, and a
--- bare time. One kind covers all three, so a column of timestamps and a column
--- of clock times read the same.
local DATE_PATTERNS = {
  "^%d%d%d%d%-%d%d" .. DATE_BODY,
  "^%d%d?/%d%d?/" .. DATE_BODY,
  "^%d%d:%d%d" .. DATE_BODY,
}

---@param value string
---@return boolean
local function is_date(value)
  for _, pattern in ipairs(DATE_PATTERNS) do
    if value:match(pattern) then
      return true
    end
  end
  return false
end

--- The value at `fraction` through a sorted list.
---@param sorted integer[]
---@param fraction number
---@return integer
local function percentile(sorted, fraction)
  local index = math.ceil(fraction * #sorted)
  return sorted[math.max(1, math.min(index, #sorted))]
end

--- Decide how one column reads from its sampled values. A single unparseable
--- value makes the column text, so a column only reads as a number, or as a
--- date, when every sampled value is one. No value is both, since none of the
--- date shapes casts to a number.
---@param values string[]
---@return csv.Format
function M.analyze_column(values)
  local decimals = {}
  local numeric = true
  local all_dates = true
  local has_values = false

  for _, value in ipairs(values) do
    if value ~= "" then
      has_values = true
      if numeric then
        local count = M.decimals(value)
        if count then
          table.insert(decimals, count)
        else
          numeric = false
        end
      end
      all_dates = all_dates and is_date(value)
    end
  end

  if not has_values then
    return M.plain()
  end
  if all_dates then
    return { kind = "date", precision = 0 }
  end
  if not numeric then
    return M.plain()
  end

  table.sort(decimals)
  -- The last few values of a float32 column can need more decimals than the
  -- rest, so the high percentile keeps one row in six hundred from widening
  -- every row. Under a hundred values it resolves to the maximum, so a small
  -- file formats to whatever its widest value needs.
  local precision = percentile(decimals, 0.99)
  if precision == 0 then
    return { kind = "int", precision = 0 }
  end
  return { kind = "float", precision = math.min(precision, MAX_PRECISION) }
end

--- Decide how every column reads. `csv-table.reader.commands` renames the
--- columns to their ids before writing the sample, so a JSON key is a column id
--- as a string.
---@param sample table<string, string>[]
---@param columns csv.Column[]
---@return table<integer, csv.Format>
function M.analyze(sample, columns)
  local formats = {}
  for _, column in ipairs(columns) do
    local key = tostring(column.column_id)
    local values = {}
    for index, row in ipairs(sample) do
      local value = row[key]
      values[index] = type(value) == "string" and value or ""
    end
    formats[column.column_id] = M.analyze_column(values)
  end
  return formats
end

--- Whether a column holds numbers, which decides how it sorts, which side it
--- reads on, and whether `printf` shapes it. A date is none of those things.
---@param format csv.Format|nil
---@return boolean
function M.is_numeric(format)
  return format ~= nil and (format.kind == "int" or format.kind == "float")
end

--- The side a column's values sit on when the user has not chosen one.
---@param format csv.Format
---@return "left"|"right"
function M.natural_align(format)
  return M.is_numeric(format) and "right" or "left"
end

M.MAX_PRECISION = MAX_PRECISION

return M
