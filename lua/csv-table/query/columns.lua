--[[
The `csv.Query` methods that decide which columns are drawn and in what order.

`query.columns` is the one stored list. A column's position in it is the display
order, and its `column_id` is the file order, so every xan stage takes the id and
the drawn table takes the position.
]]

local M = {}

--- The columns on display, in display order. A column's position here is its
--- column number, and the same position in `page.ranges` is the cell it is drawn
--- in.
---@return csv.Column[]
function M.display_columns(self)
  local display = {}
  for _, column in ipairs(self.columns) do
    if not column.hidden then
      table.insert(display, column)
    end
  end
  return display
end

---@param column csv.Column
---@return integer|nil
local function index_of(self, column)
  for index, candidate in ipairs(self.columns) do
    if candidate.column_id == column.column_id then
      return index
    end
  end
  return nil
end

---@param column csv.Column
function M.hide_column(_, column)
  column.hidden = true
end

--- Hide a column and keep it on the clipboard. `append` adds to a cut already
--- there, which is how several columns move together.
---@param column csv.Column
---@param append boolean
function M.cut_column(self, column, append)
  if not append then
    self.clipboard = {}
  end
  for _, held in ipairs(self.clipboard) do
    if held.column_id == column.column_id then
      column.hidden = true
      return
    end
  end
  table.insert(self.clipboard, column)
  column.hidden = true
end

--- Put the held columns back, beside `column`, in the order they were cut.
---@param column csv.Column|nil Paste at the end when absent.
---@param before boolean
---@return boolean pasted
function M.paste_columns(self, column, before)
  if #self.clipboard == 0 then
    return false
  end

  for _, held in ipairs(self.clipboard) do
    local from = index_of(self, held)
    if from then
      table.remove(self.columns, from)
    end
  end

  local at = #self.columns + 1
  local position = column and index_of(self, column)
  if position then
    at = before and position or position + 1
  end

  for offset, held in ipairs(self.clipboard) do
    held.hidden = false
    table.insert(self.columns, at + offset - 1, held)
  end
  self.clipboard = {}
  return true
end

--- Exchange a column with the visible column `delta` places away. The two swap
--- in place, leaving any hidden column between them where it sits.
---@param column csv.Column
---@param delta integer
---@return boolean moved True when the column had a neighbor to trade with.
function M.swap_columns(self, column, delta)
  local index = index_of(self, column)
  if not index then
    return false
  end

  local step = delta > 0 and 1 or -1
  local remaining = math.abs(delta)
  local target = index
  while remaining > 0 do
    target = target + step
    if target < 1 or target > #self.columns then
      return false
    end
    if not self.columns[target].hidden then
      remaining = remaining - 1
    end
  end

  self.columns[index], self.columns[target] = self.columns[target], self.columns[index]
  return true
end

--- Show every column again, back in file order.
function M.show_all_columns(self)
  for _, column in ipairs(self.columns) do
    column.hidden = false
  end
  table.sort(self.columns, function(left, right)
    return left.column_id < right.column_id
  end)
  self.columns_filtered_to_marks = false
end

--- Show only the marked columns, or every column if already restricted.
function M.show_marked_columns_only(self)
  if self.columns_filtered_to_marks then
    return M.show_all_columns(self)
  end

  local any = false
  for _, column in ipairs(self.columns) do
    if self.marked_columns[column.column_id] then
      any = true
      break
    end
  end
  if not any then
    return
  end

  for _, column in ipairs(self.columns) do
    column.hidden = not self.marked_columns[column.column_id]
  end
  self.columns_filtered_to_marks = true
end

return M
