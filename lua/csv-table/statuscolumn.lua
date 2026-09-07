--[[
The row number in the gutter.

The number a row is drawn under counts within the current filter and sort and
runs on across pages, so it is a fact about the view rather than a value in the
file. nvim draws it: `'statuscolumn'` calls `text` once per line, and
`csv-table.layout` already knows which row that line holds.

The width comes from the last row on the page, so every number on a page is
drawn at the same width and the table starts at the same screen column.
]]

local layout = require("csv-table.layout")

local M = {}

M.EXPRESSION = "%!v:lua.require'csv-table.statuscolumn'.text()"

--- How many characters the widest row number on the page takes.
---@param buf csv.Buffer
---@return integer
local function width(buf)
  local last = layout.row_at_line(buf.layout, buf.layout.last_line)
  return last and #tostring(last.row_number) or 1
end

--- The gutter text for the line nvim is drawing, which it hands over in
--- `v:lnum`. The header and the border lines take blanks, so the table keeps its
--- alignment down the whole buffer.
---@return string
function M.text()
  -- Required here because `csv-table.buffer` sets the option this belongs to.
  local buf = require("csv-table.buffer").get(vim.api.nvim_get_current_buf())
  if not buf or not buf.layout then
    return ""
  end

  local room = width(buf)
  local row = layout.row_at_line(buf.layout, vim.v.lnum)
  if not row then
    return string.rep(" ", room + 1)
  end
  return string.format("%%#CsvRowNumber#%" .. room .. "d ", row.row_number)
end

return M
