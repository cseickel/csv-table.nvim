--[[
Draws the row number in the gutter.

The number counts within the current filter and sort and runs on across pages.
Its width comes from the last row on the page, so the table starts at the same
screen column on every line.
]]

local M = {}

M.EXPRESSION = "%!v:lua.require'csv-table.buffer.statuscolumn'.text()"

--- How many characters the widest row number on the page takes.
---@param buf csv.Buffer
---@return integer
local function width(buf)
  local last_row = buf.page:row_at_line(buf.page.last_line)
  return last_row and #tostring(last_row.row_number) or 1
end

--- The gutter text for one line. nvim names the window it is drawing in
--- `g:statusline_winid` and the line in `v:lnum`. The header and the border lines
--- get blanks of the same width, so the table stays aligned down the whole buffer.
---@return string
function M.text()
  local window = vim.g.statusline_winid
  if not window or not vim.api.nvim_win_is_valid(window) then
    return ""
  end

  -- Required here because `csv-table.buffer` requires this module.
  local buf = require("csv-table.buffer").get(vim.api.nvim_win_get_buf(window))
  if not buf then
    return ""
  end

  local number_width = width(buf)
  local row = buf.page:row_at_line(vim.v.lnum)
  if not row then
    return string.rep(" ", number_width + 1)
  end
  return string.format("%%#CsvRowNumber#%" .. number_width .. "d ", row.row_number)
end

return M
