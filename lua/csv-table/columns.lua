--[[
Columns: what one is, and which of them the table draws.

A column is named by its `column_id`, the 0-based position it holds in the
source file, which every xan stage accepts in place of a header name.

A column also has a `label`, the header text with its occurrence appended where
a name repeats. That is the name the user reads, in the drawn header and in
every panel, and it is what `csv-table.commands` keys a JSON object by, both of
which need one name per column.

`state.columns` is the one list. It holds every source column, and the user
reorders it and sets `hidden` on its entries, so `column_id` gives the file
order and a position in the list gives the display order. The table draws the
visible entries, in that order.
]]

local M = {}

---@class csv.Column
---@field name string      Header text exactly as it appears in the file.
---@field label string     The name shown to the user, unique across the file.
---@field column_id integer 0-based position among the file's columns. The row
---                        id the pipeline prepends takes -1.
---@field hidden boolean   True when the user has taken the column off display.

--- Build the column list from the lines of `xan headers -j`, in file order and
--- all on display.
---
--- A repeated header takes its occurrence as a suffix, so `a,b,a` labels its
--- columns `a[0]`, `b` and `a[1]`. That gives the user one name per column to
--- read, and gives `to jsonl` one key per column to write.
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
      label = totals[name] > 1 and (name .. "[" .. nth .. "]") or name,
      column_id = i - 1,
      hidden = false,
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

--- Render a moonblade string literal.
---@param value string
---@return string
function M.string_literal(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- Which columns the table draws -----------------------------------------------

--- The columns on display, in display order. A column's position here is its
--- `column_number`, and the same position in `layout.ranges` is the cell it is
--- drawn in.
---@param state csv.State
---@return csv.Column[]
function M.display_columns(state)
  local display = {}
  for _, column in ipairs(state.columns) do
    if not column.hidden then
      table.insert(display, column)
    end
  end
  return display
end

---@param state csv.State
---@param column csv.Column
---@return integer|nil
local function index_of(state, column)
  for index, candidate in ipairs(state.columns) do
    if candidate.column_id == column.column_id then
      return index
    end
  end
  return nil
end

---@param column csv.Column
function M.hide(column)
  column.hidden = true
end

--- Hide a column and keep it on the clipboard. `append` adds to a cut already
--- there, which is how several columns move together.
---@param state csv.State
---@param column csv.Column
---@param append boolean
function M.cut(state, column, append)
  if not append then
    state.clipboard = {}
  end
  for _, held in ipairs(state.clipboard) do
    if held.column_id == column.column_id then
      return M.hide(column)
    end
  end
  table.insert(state.clipboard, column)
  M.hide(column)
end

--- Put the held columns back, beside `column`, in the order they were cut.
---@param state csv.State
---@param column csv.Column|nil Paste at the end when absent.
---@param before boolean
---@return boolean pasted
function M.paste(state, column, before)
  if #state.clipboard == 0 then
    return false
  end

  for _, held in ipairs(state.clipboard) do
    local from = index_of(state, held)
    if from then
      table.remove(state.columns, from)
    end
  end

  local at = #state.columns + 1
  local position = column and index_of(state, column)
  if position then
    at = before and position or position + 1
  end

  for offset, held in ipairs(state.clipboard) do
    held.hidden = false
    table.insert(state.columns, at + offset - 1, held)
  end
  state.clipboard = {}
  return true
end

--- Exchange a column with the visible column `delta` places away. The two swap
--- in place, leaving any hidden column between them where it sits.
---@param state csv.State
---@param column csv.Column
---@param delta integer
---@return boolean moved True when the column had a neighbor to trade with.
function M.swap(state, column, delta)
  local index = index_of(state, column)
  if not index then
    return false
  end

  local step = delta > 0 and 1 or -1
  local remaining = math.abs(delta)
  local target = index
  while remaining > 0 do
    target = target + step
    if target < 1 or target > #state.columns then
      return false
    end
    if not state.columns[target].hidden then
      remaining = remaining - 1
    end
  end

  state.columns[index], state.columns[target] = state.columns[target], state.columns[index]
  return true
end

--- Show every column again, back in file order.
---@param state csv.State
function M.show_all(state)
  for _, column in ipairs(state.columns) do
    column.hidden = false
  end
  table.sort(state.columns, function(left, right)
    return left.column_id < right.column_id
  end)
  state.columns_filtered_to_marks = false
end

--- Show only the marked columns, or every column if already restricted.
---@param state csv.State
function M.show_marked_only(state)
  if state.columns_filtered_to_marks then
    return M.show_all(state)
  end

  local any = false
  for _, column in ipairs(state.columns) do
    if state.marked_columns[column.column_id] then
      any = true
      break
    end
  end
  if not any then
    return
  end

  for _, column in ipairs(state.columns) do
    column.hidden = not state.marked_columns[column.column_id]
  end
  state.columns_filtered_to_marks = true
end

return M
