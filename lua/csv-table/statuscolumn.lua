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
---
--- nvim draws every window, so the buffer comes from `g:statusline_winid`, the
--- window being drawn. Reading the current buffer would answer for the window
--- the user is in and leave every other window's gutter blank.
---@return string
function M.text()
  -- Required here because `csv-table.buffer` sets the option this belongs to.
  local window = vim.g.statusline_winid
  if not window or not vim.api.nvim_win_is_valid(window) then
    return ""
  end

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
