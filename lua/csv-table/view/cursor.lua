--[[
The `csv.View` methods that drive the real nvim cursor, which is hidden and parked
at one edge of the active cell.

`physical_cell` and `moved_cell` are the only way back from the cursor to a cell,
and they answer for a move nvim made on its own: a click, a search, `gv`, or any
motion this plugin does not map.
]]

local page = require("csv-table.page")

local M = {}

--- Characters kept on screen past the active cell, which is what shows the cell's
--- border and a slice of the next column for orientation.
local PREVIEW = 8

--- The last column is set to 0, so the right border is at the edge of the screen
--- and does not scroll past it. Every other column uses the preview value.
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
--- stays in the same cell keeps the end it had. nvim scrolls sideways only far
--- enough to show the byte the cursor is on, so the far end is what brings the
--- whole cell into view.
---
--- The position recorded is the one nvim reports back, because nvim moves a
--- cursor set inside a multi-byte character to the start of that character.
---@param cell csv.Cell
local function park(self, cell)
  local drawn = self.buffer.page
  local column_number = drawn:column_number(cell.column)
  if not column_number then
    return
  end
  local range = drawn:cell_ranges(cell.row.buffer_line)[column_number]
  if not range then
    return
  end

  -- The column alone, so a render that drops the row still keeps the end the
  -- cursor was parked at.
  local previous = self.active and drawn:column_by_id(self.active.column_id)
  local was = previous and drawn:column_number(previous)

  local edge = "left"
  if was and column_number > was then
    edge = "right"
  elseif was == column_number then
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

--- Whether the real cursor has left the byte the active cell parked it on, which
--- is what says the user moved it.
---@return boolean
function M.cursor_moved(self)
  if not self.active then
    return true
  end
  local position = vim.api.nvim_win_get_cursor(self.window)
  return position[1] ~= self.position[1] or position[2] ~= self.position[2]
end

--- The cell the real cursor is in, which is where nvim left it rather than where
--- the plugin put it.
---@return csv.Cell|nil
function M.physical_cell(self)
  local position = vim.api.nvim_win_get_cursor(self.window)
  return self.buffer.page:cell_at(position[1], position[2])
end

--- The cell a move of the real cursor was aiming for.
---
--- A cursor that landed in another cell names that cell, which is what a click, a
--- search or `$` means. A cursor still inside the cell it started in was moved by
--- something too small to leave it, such as `l` in a cell drawn twenty wide, and
--- the cell one step that way is what was meant.
---
--- Sideways is the only direction that can be meant here, so a cursor that kept
--- its byte kept its cell. `k` on the first row of the page is that: the cursor
--- reaches the border line above and `cell_at` brings it back.
---@return csv.Cell|nil
function M.moved_cell(self)
  local landed = self:physical_cell()
  if not landed or not self.active then
    return landed
  end

  local stayed = landed.row.row_id == self.active.row_id
    and landed.column.column_id == self.active.column_id
  local byte = vim.api.nvim_win_get_cursor(self.window)[2]
  if not stayed or byte == self.position[2] then
    return landed
  end

  local columns = byte > self.position[2] and 1 or -1
  return self.buffer.page:step_cell(landed, { rows = 0, columns = columns })
end

--- Make `cell` active and park the real cursor in it.
---@param cell csv.Cell|nil
---@return csv.Cell|nil
function M.move_to(self, cell)
  if not cell or not self.buffer.page:column_number(cell.column) then
    return nil
  end

  -- An action that opened a popup or waited for xan comes back here holding a view
  -- of a window the user has since closed or taken elsewhere.
  if not self:on_screen() then
    return nil
  end

  -- nvim empties the buffer before a read command refills it, so between the two
  -- the page names lines the buffer does not hold.
  if cell.row.buffer_line > vim.api.nvim_buf_line_count(self.buffer.bufnr) then
    return nil
  end

  park(self, cell)
  return cell
end

--- Take the active cell `rows` rows and `columns` columns from where it is,
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

--- Put the active cell back after a render, taking the row and the column by id,
--- so a sort or a filter that keeps them takes the user along. Either id that has
--- left the page falls back to where the cursor is parked: its line for the row,
--- its byte for the column.
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
