--[[
Draws the row number in the gutter.

- `EXPRESSION` is the `'statuscolumn'` value `buffer.attach` sets
- `text` answers for the line nvim is drawing

The number counts within the current filter and sort and runs on across pages,
so it is a fact about the view rather than a value in the file. Its width comes
from the last row on the page, so the table starts at the same screen column on
every line.
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
---
--- nvim draws every window on screen and names the one it is drawing in
--- `g:statusline_winid`, which is the window this answers for.
---@return string
function M.text()
  local window = vim.g.statusline_winid
  if not window or not vim.api.nvim_win_is_valid(window) then
    return ""
  end

  -- Required here because `csv-table.buffer` requires this module to set the
  -- option in the first place.
  local buf = require("csv-table.buffer").get(vim.api.nvim_win_get_buf(window))
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
