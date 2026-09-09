--[[
The `csv.Query` methods that order the rows.

Every one of them goes back to the first page, because the rows the page held are
now somewhere else in the result.
]]

local M = {}

--- Sort by one column alone. Asking again for the direction it already has clears
--- the sort, which is how a sort is undone.
---@param column csv.Column
---@param direction "asc"|"desc"
function M.sort_by(self, column, direction)
  local only = #self.sort_keys == 1 and self.sort_keys[1]
  if only and only.column.column_id == column.column_id and only.direction == direction then
    self.sort_keys = {}
  else
    self.sort_keys = {
      { column = column, direction = direction, numeric = self:is_numeric(column) },
    }
  end
  self.page_number = 0
end

--- Add a less significant sort key, or change the direction of one already
--- present. Asking again for the direction it already has removes that key.
---@param column csv.Column
---@param direction "asc"|"desc"
function M.add_sort_key(self, column, direction)
  for index, key in ipairs(self.sort_keys) do
    if key.column.column_id == column.column_id then
      if key.direction == direction then
        table.remove(self.sort_keys, index)
      else
        key.direction = direction
      end
      self.page_number = 0
      return
    end
  end

  table.insert(self.sort_keys, {
    column = column,
    direction = direction,
    numeric = self:is_numeric(column),
  })
  self.page_number = 0
end

---@param column csv.Column
function M.remove_sort_key(self, column)
  for index, key in ipairs(self.sort_keys) do
    if key.column.column_id == column.column_id then
      table.remove(self.sort_keys, index)
      self.page_number = 0
      return
    end
  end
end

function M.clear_sort(self)
  self.sort_keys = {}
  self.page_number = 0
end

return M
