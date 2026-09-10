--[[
The `csv.View` methods that keep nvim's own visual region on the same block as the
selected cells.

- `set_visual` hands nvim the anchor
- `take_visual` reads back the anchor nvim holds

Nvim keeps a visual region as one end it holds and one end the cursor drives, and
the cursor is already the active cell, so the anchor is the only end to carry
across. `getpos("v")` reads it while the mode runs. `'<` and `'>` are written by
`mark_selection` and outlive the mode.
]]

local mode = require("csv-table.utils.mode")
local page = require("csv-table.page")

local M = {}

--- The byte in `cell` on the side away from `toward`, so nvim's region reaches the
--- outer edge of the anchor cell rather than stopping inside it.
---@param cell csv.Cell
---@param toward csv.Cell
---@return integer[]|nil A line and a byte, as nvim takes a cursor.
local function outer_edge(self, cell, toward)
  local drawn = self.buffer.page
  local column_number = drawn:column_number(cell.column)
  local other = drawn:column_number(toward.column)
  if not column_number or not other then
    return nil
  end

  local from, to = drawn:cell_bounds(cell.row.buffer_line, column_number)
  if not from then
    return nil
  end
  return { cell.row.buffer_line, column_number > other and to - 1 or from }
end

--- Put nvim's anchor on the anchor cell, so nvim's visual region covers the block
--- the table has picked out and every move from here takes both.
---
--- Nvim's `o` makes the end the cursor is on the one it holds, so parking the
--- cursor on the anchor cell and pressing it hands the anchor over. The cursor
--- lands on whichever end nvim was holding, and goes back where it was parked.
function M.set_visual(self)
  if not mode.in_visual() or not self:on_screen() or not self:is_current() then
    return
  end

  local drawn = self.buffer.page
  local anchor = drawn:cell_of(self.anchor)
  local head = drawn:cell_of(self.head)
  local at = anchor and head and outer_edge(self, anchor, head)
  -- `normal! o` cannot be undone once it has run, so the line is checked here
  -- rather than left to the cursor call to throw. A render empties the buffer
  -- before it refills it, and between the two the page names lines that are gone.
  if not at or at[1] > vim.api.nvim_buf_line_count(self.buffer.bufnr) then
    return
  end

  -- Appended rather than assigned, because another plugin may be part way through
  -- its own window bookkeeping with `eventignore` set to `all`.
  local ignored = vim.o.eventignore
  vim.opt.eventignore:append("CursorMoved")
  pcall(function()
    vim.api.nvim_win_set_cursor(self.window, at)
    vim.cmd("normal! o")
    vim.api.nvim_win_set_cursor(self.window, self.position)
  end)
  vim.o.eventignore = ignored
end

--- Take the anchor from the one nvim holds, so a mapping of the user's that moved
--- the far end of the visual region is followed. `cell_at` clamps to the page, so an
--- anchor left on a border line comes back as the nearest row.
function M.take_visual(self)
  if not mode.in_visual() or not self:on_screen() or not self:is_current() then
    return
  end

  local at = vim.fn.getpos("v")
  local cell = self.buffer.page:cell_at(at[2], at[3] - 1)
  if cell then
    self.anchor = page.ref_of(cell)
  end
end

return M
