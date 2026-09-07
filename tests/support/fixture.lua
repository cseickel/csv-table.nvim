--[[
A state to run assertions against.

Every spec starts from the same three column file, so a position in one spec
means the same thing in the next.
]]

local columns = require("csv-table.columns")
local state = require("csv-table.state")

local M = {}

--- A state over a file whose headers are `a,b,a`, which is the shape that
--- exercises the label suffix a repeated header takes.
---
--- The second return value is the columns in file order, in a list of its own,
--- so a spec that reorders `state.columns` can still name the column it means.
---@return csv.State
---@return csv.Column[] source_columns
function M.duplicated_headers()
  local source_columns = columns.from_names({ "a", "b", "a" })

  local by_file_order = {}
  for index, column in ipairs(source_columns) do
    by_file_order[index] = column
  end

  return state.new({
    path = "test.csv",
    sheet = 0,
    sheets = {},
    columns = source_columns,
    rowid_name = "id",
    formats = {},
  }), by_file_order
end

return M
