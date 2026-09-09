--[[
A query to run assertions against.

Every spec starts from the same three column file, so a position in one spec means
the same thing in the next.
]]

local file = require("csv-table.file")
local query = require("csv-table.query")

local M = {}

--- A reader that records what it was asked rather than running xan. `answer` is
--- the count it hands back, absent when a spec only counts the asking.
---@return table
function M.reader()
  return {
    counts = 0,
    answer = nil,
    count = function(self, _, on_count)
      self.counts = self.counts + 1
      if self.answer then
        on_count(self.answer)
      end
    end,
  }
end

--- A query over a file whose headers are `a,b,a`, which is the shape that
--- exercises the label suffix a repeated header takes.
---
--- The second return value is the columns in file order, which the query never
--- reorders, so a spec that moves a column can still name the one it means.
---@return csv.Query
---@return csv.Column[] source_columns
---@return table reader
function M.duplicated_headers()
  local reader = M.reader()
  local source = file.new({
    path = "test.csv",
    sheet = 0,
    sheets = {},
    columns = file.columns_from_names({ "a", "b", "a" }),
    formats = {},
    rowid_name = "id",
  })

  return query.new(source, reader, function() end), source.columns, reader
end

return M
