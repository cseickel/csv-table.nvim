--[[
Column identity.

A CSV file may repeat a header name, so a name alone does not identify a column.
Every column is a `csv.Column`, and this module owns the four
renderings xan needs: the selection syntax used by `select` and `sort -s`, the
moonblade form used inside filter expressions, the display name shown in the
buffer, and the `rename` argument that puts those display names on the output.
]]

local M = {}

---@class csv.Column
---@field name string     Header text exactly as it appears in the file.
---@field nth integer     0-based occurrence among columns sharing `name`.
---@field index integer   0-based position among the file's columns.
---@field duplicated boolean True when another column shares `name`.

--- Build the column list from the lines of `xan headers -j`.
---@param names string[]
---@return csv.Column[]
function M.from_names(names)
  local totals = {}
  for _, name in ipairs(names) do
    totals[name] = (totals[name] or 0) + 1
  end

  local seen = {}
  local columns = {}
  for i, name in ipairs(names) do
    local nth = seen[name] or 0
    seen[name] = nth + 1
    columns[i] = {
      name = name,
      nth = nth,
      index = i - 1,
      duplicated = totals[name] > 1,
    }
  end
  return columns
end

--- How many characters a value holds, which is what xan's padding counts. The
--- `#` operator counts bytes, and a sort arrow in a header is three of them.
---@param value string
---@return integer
function M.text_length(value)
  local _, count = value:gsub("[^\128-\191]", "")
  return count
end

--- The first `length` characters of a value, ending in an ellipsis when
--- anything was dropped. Counting characters rather than bytes keeps a
--- multi-byte character from being cut in half.
---@param value string
---@param length integer
---@return string
function M.truncate(value, length)
  if M.text_length(value) <= length then
    return value
  end
  if length <= 1 then
    return "…"
  end

  local kept = {}
  for character in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #kept + 1 >= length then
      break
    end
    kept[#kept + 1] = character
  end
  return table.concat(kept) .. "…"
end

--- Wrap a value in double quotes, doubling any it contains.
---@param value string
---@return string
local function csv_quote(value)
  return '"' .. value:gsub('"', '""') .. '"'
end

--- Render a name as one token of a xan selection argument. xan reads `*`, `:`,
--- `!`, `[` and `]` as selection syntax, so a bare `has:colon` asks for a column
--- named `has`, and quoting the name stops that.
---
--- A name holding a double quote goes bare instead. xan reads `""` inside a
--- quoted name as two characters rather than as one, so quoting `va"l` asks for
--- `va""l` and the run fails, while a bare double quote is not selection syntax
--- and resolves. A name holding a double quote and a syntax character both
--- cannot be named at all.
---@param name string
---@return string
function M.quote_name(name)
  if name:find('"', 1, true) then
    return name
  end
  return name:match("^[%w_]+$") and name or csv_quote(name)
end

--- Render for a xan selection argument (`select`, `sort -s`, `frequency -s`).
--- The bare form of a name always resolves to its first occurrence, so the
--- `[nth]` suffix is only needed past occurrence zero.
---@param column csv.Column
---@return string
function M.selector(column)
  local base = M.quote_name(column.name)
  if column.nth == 0 then
    return base
  end
  return base .. "[" .. column.nth .. "]"
end

--- Render a comma-joined selection argument for several columns, in order.
---@param columns csv.Column[]
---@return string
function M.selection(columns)
  local parts = {}
  for i, column in ipairs(columns) do
    parts[i] = M.selector(column)
  end
  return table.concat(parts, ",")
end

--- Render a moonblade string literal.
---@param value string
---@return string
function M.string_literal(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- Render for use inside a moonblade expression (`filter`, `map`).
--- Always the two-argument `col` form: a bare identifier would be shorter but
--- would need its own rules for names that are not valid identifiers.
---@param column csv.Column
---@return string
function M.expression(column)
  return string.format("col(%s, %d)", M.string_literal(column.name), column.nth)
end

--- The name shown to the user. Only a duplicated name gets its occurrence.
---@param column csv.Column
---@return string
function M.display(column)
  if not column.duplicated then
    return column.name
  end
  return column.name .. "[" .. column.nth .. "]"
end

--- Render the argument for `xan rename`, which takes one CSV row of names
--- covering every column of its input, in order.
---@param names string[]
---@return string
function M.rename_argument(names)
  local parts = {}
  for i, name in ipairs(names) do
    parts[i] = name:match('[,"\r\n]') and csv_quote(name) or name
  end
  return table.concat(parts, ",")
end

--- The display names of `columns`, in order.
---@param columns csv.Column[]
---@return string[]
function M.display_names(columns)
  local names = {}
  for i, column in ipairs(columns) do
    names[i] = M.display(column)
  end
  return names
end

return M
