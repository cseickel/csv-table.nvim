local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local query = require("csv-table.query")

local M = {}

---@class csv.Action
---@field description string
---@field run fun(buf: csv.Buffer)

---@param description string
---@param run fun(buf: csv.Buffer)
---@return csv.Action
M.action = function (description, run)
  return { description = description, run = run }
end

--- The column under the cursor, or nothing and a word about why. The row id and
--- the borders are not columns, so a key pressed over either has nothing to act
--- on and says so rather than appearing dead.
---@param buf csv.Buffer
---@return csv.Column|nil
M.column_under_cursor = function (buf)
  local column = cursor.column_at(buf, 0)
  if not column then
    query.report("the cursor is not on a column")
  end
  return column
end

--- Run `change` against the column under the cursor, then repaint.
---@param buf csv.Buffer
---@param change fun(column: csv.Column)
M.on_column = function (buf, change)
  local column = M.column_under_cursor(buf)
  if not column then
    return
  end
  change(column)
  buffer.render(buf)
end

return M
