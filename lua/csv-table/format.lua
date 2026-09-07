--[[
What kind of value each column holds.

A CSV cell is text, so nothing in the file says what a column means. This module
decides, from a sample of rows, which columns hold numbers and how many decimals
each one needs, and which hold dates. `csv-table.pipeline` turns the numeric
decisions into the `printf` clauses that xan applies, and `csv-table.highlight`
colors a cell from the kind of the column it is in.

Precision is measured after snapping each value to seven significant digits,
because a column printed from float32 has noise past that point: a price of
`199.59` reaches the file as `199.589996338`, which reads as nine decimals.
]]

local columns = require("csv-table.columns")

local M = {}

---@class csv.Format
---@field kind "int"|"float"|"date"|"text"
---@field precision integer Decimals to print. Zero unless `kind` is "float".
---@field width integer|nil Characters every value is padded to. Absent until the user asks for padding.
---@field align "left"|"center"|"right"|nil Which side the padding goes. Absent alongside `width`.
---@field spec string|nil A printf specification, replacing every other rule.

local MAX_PRECISION = 6
local SIGNIFICANT_DIGITS = 7

--- Decimals a value needs once its float noise is gone, or nil when the value
--- is not a number.
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

--- Whether a value reads as a date or a time.
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

--- Decide how one column reads from its sampled values.
--- A single unparseable value makes the column text, so a column only reads as
--- a number, or as a date, when every sampled value is one. No value is both,
--- since none of the date shapes casts to a number.
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
    return { kind = "text", precision = 0 }
  end
  if all_dates then
    return { kind = "date", precision = 0 }
  end
  if not numeric then
    return { kind = "text", precision = 0 }
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

--- Decide how every column reads. `csv-table.commands` renames the columns to
--- their ids before writing the sample, so a JSON key is a column id as a
--- string.
---@param sample table<string, string>[] Sample rows, keyed by column id.
---@param source_columns csv.Column[]
---@return table<integer, csv.Format>
function M.analyze(sample, source_columns)
  local formats = {}
  for _, column in ipairs(source_columns) do
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

--- The format for `column`, creating a plain one if the sample never saw it.
---@param formats table<integer, csv.Format>
---@param column csv.Column
---@return csv.Format
local function format_for(formats, column)
  local format = formats[column.column_id]
  if not format then
    format = { kind = "text", precision = 0 }
    formats[column.column_id] = format
  end
  return format
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
local function natural_align(format)
  return M.is_numeric(format) and "right" or "left"
end

--- The width the user is working from: the one they asked for, or the column as
--- it is drawn when they have not asked yet. The sample this module analyzes can
--- miss the longest value in the file, and the column is drawn to fit the
--- longest value on the page, so the drawn width is the only honest starting
--- point. Reading it back from the format afterwards is what keeps a run of
--- width presses stepping one at a time, since a render may not have landed.
---@param formats table<integer, csv.Format>
---@param column csv.Column
---@param drawn_width integer Characters the column is drawn in.
---@return integer
function M.working_width(formats, column, drawn_width)
  local format = formats[column.column_id]
  return format and format.width or drawn_width
end

--- Show more or fewer decimals. Asking for decimals on a column that is not a
--- number makes it a float, since that is what the request means.
---@param formats table<integer, csv.Format>
---@param column csv.Column
---@param delta integer
function M.adjust_precision(formats, column, delta)
  local format = format_for(formats, column)
  format.precision = math.max(0, math.min(format.precision + delta, MAX_PRECISION))
  format.kind = format.precision > 0 and "float" or "int"
end

--- Use a printf specification instead of every other formatting rule. An empty
--- specification returns the column to the detected format.
---@param formats table<integer, csv.Format>
---@param column csv.Column
---@param spec string
function M.set_spec(formats, column, spec)
  format_for(formats, column).spec = spec ~= "" and spec or nil
end

--- Pad every value of a column to `width` characters, cutting the longer ones.
--- Padding needs a side to pad towards, so an alignment the user has not chosen
--- settles to the side the column's kind reads on.
---@param formats table<integer, csv.Format>
---@param column csv.Column
---@param opts { width: integer, align: "left"|"center"|"right"|nil }
function M.set_padding(formats, column, opts)
  local format = format_for(formats, column)
  format.width = math.max(1, opts.width)
  format.align = opts.align or format.align or natural_align(format)
end

return M
