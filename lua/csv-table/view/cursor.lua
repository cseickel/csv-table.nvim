--[[
The `csv.View` methods that drive the real nvim cursor, which is hidden and parked
at one edge of the active cell.

The cursor is also the way back to a cell from a move nvim made on its own: a
click, a search, `gv`, or any motion this plugin does not map.
]]

local page = require("csv-table.page")

local M = {}

--- Characters kept on screen past the active cell, showing its border and a slice
--- of the next column.
local PREVIEW = 8

--- 0 on the last column, so the right border sits at the edge of the screen
--- instead of scrolling past it.
---@param column_number integer
---@return integer
local function scroll_off(self, column_number)
  if column_number == self.buffer.page:column_count() then
    return 0
  end
  return PREVIEW
end

--- Park the real cursor in `cell` and draw it. The cursor takes the last byte of
--- the cell when moving right and the first when moving left, and a move that
--- stays in the same cell keeps the end it had, because nvim scrolls sideways only
--- far enough to show the byte the cursor is on.
---
--- The position recorded is the one nvim reports back, because nvim moves a
--- cursor set inside a multi-byte character to the start of that character.
---@param cell csv.Cell
local function park(self, cell)
  local current_page = self.buffer.page
  local column_number = current_page:column_number(cell.column)
  if not column_number then
    return
  end
  local range = current_page:cell_ranges(cell.row.buffer_line)[column_number]
  if not range then
    return
  end

  -- The column alone is compared, so a render that drops the row still keeps the
  -- end the cursor was parked at.
  local previous_column = self.active and current_page:column_by_id(self.active.column_id)
  local previous_number = previous_column and current_page:column_number(previous_column)

  local edge = "left"
  if previous_number and column_number > previous_number then
    edge = "right"
  elseif previous_number == column_number then
    edge = self.edge
  end
  self.edge = edge

  vim.wo[self.window][0].sidescrolloff = scroll_off(self, column_number)
  vim.api.nvim_win_set_cursor(self.window, {
    cell.row.buffer_line,
    edge == "right" and range.to - 1 or range.from,
  })

  self.active = page.ref_of(cell)
  self.position = vim.api.nvim_win_get_cursor(self.window)
  self:draw()
end

--- Whether the real cursor has left the byte it was parked on.
---@return boolean
function M.cursor_moved(self)
  if not self.active then
    return true
  end
  local position = vim.api.nvim_win_get_cursor(self.window)
  return position[1] ~= self.position[1] or position[2] ~= self.position[2]
end

--- The cell the real cursor is in now, wherever nvim left it.
---@return csv.Cell|nil
function M.physical_cell(self)
  local position = vim.api.nvim_win_get_cursor(self.window)
  return self.buffer.page:cell_at(position[1], position[2])
end

--- The fields of `getmousepos()` this plugin reads.
---@class csv.MousePosition
---@field winid integer
---@field line integer      0 off the text: a status line, a separator, a winbar.
---@field column integer    The byte under the pointer plus one, 0 off the text.
---@field screenrow integer
---@field screencol integer

--- The cell under the pointer, nil when the pointer is off this window's text.
---@param mouse csv.MousePosition
---@return csv.Cell|nil
function M.mouse_cell(self, mouse)
  if mouse.winid ~= self.window or mouse.line == 0 or mouse.column == 0 then
    return nil
  end
  return self.buffer.page:cell_at(mouse.line, mouse.column - 1)
end

--- The cell a move of the real cursor meant.
---
--- A cursor that landed in another cell names that cell, which is what a click, a
--- search or `$` means. A cursor still inside the cell it started in was moved by
--- something too small to leave it, `l` in a cell drawn twenty wide, and the cell
--- one step that way is what was meant.
---
--- Sideways is the only direction that can be meant, so a cursor that kept its
--- byte kept its cell. `k` on the first row of the page is one: the cursor reaches
--- the border line above and `cell_at` brings it back.
---@return csv.Cell|nil
function M.moved_cell(self)
  local cursor_cell = self:physical_cell()
  if not cursor_cell or not self.active then
    return cursor_cell
  end

  local same_cell = cursor_cell.row.row_id == self.active.row_id
    and cursor_cell.column.column_id == self.active.column_id
  local byte = vim.api.nvim_win_get_cursor(self.window)[2]
  if not same_cell or byte == self.position[2] then
    return cursor_cell
  end

  local columns = byte > self.position[2] and 1 or -1
  return self.buffer.page:step_cell(cursor_cell, { rows = 0, columns = columns })
end

--- Make `cell` active and park the real cursor in it.
---@param cell csv.Cell|nil
---@return csv.Cell|nil
function M.move_to(self, cell)
  if not cell or not self.buffer.page:column_number(cell.column) then
    return nil
  end

  -- An action that opened a popup or waited for xan comes back holding a view of a
  -- window the user has since closed or moved to another buffer.
  if not self:on_screen() then
    return nil
  end

  -- nvim empties the buffer before a read command refills it, and between the two
  -- the page names lines the buffer does not hold.
  if cell.row.buffer_line > vim.api.nvim_buf_line_count(self.buffer.bufnr) then
    return nil
  end

  park(self, cell)
  return cell
end

--- Move the active cell `rows` rows and `columns` columns from where it is,
--- leaving the selection alone.
---@param rows integer
---@param columns integer
---@return csv.Cell|nil
function M.move_by(self, rows, columns)
  local cell = self:active_cell()
  if not cell then
    return nil
  end
  return self:move_to(self.buffer.page:step_cell(cell, { rows = rows, columns = columns }))
end

--- Put the active cell back after a render, finding the row and the column by id,
--- so a sort or filter that keeps them keeps the user on them. An id that has left
--- the page falls back to where the cursor is parked: its line for the row, its
--- byte for the column.
---@return csv.Cell|nil
function M.restore(self)
  local cell = self:physical_cell()
  if cell and self.active then
    cell.row = self.buffer.page:row_by_id(self.active.row_id) or cell.row
    cell.column = self.buffer.page:column_by_id(self.active.column_id) or cell.column
  end
  return self:move_to(cell)
end

return M
