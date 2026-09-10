--[[
The `csv.View` methods that move the active cell and the head of the selection
together.

A plain move leaves the selection where the user put it. A move extends it when
the key was shift keyed, or when nvim is in a visual mode. Nvim owns that mode, so
a remapped `<C-v>` and any plugin that starts visual mode both count, and nothing
here has to be told which key was pressed.
]]

local mode = require("csv-table.utils.mode")

local M = {}

--- The axes a visual mode bounds. Charwise and blockwise both pick out a block of
--- cells, since a selection is cells rather than the text they are painted in,
--- and `V` is whole rows.
---@return csv.SelectionKind
local function kind_of_mode()
  return vim.fn.mode() == "V" and "row" or "cell"
end

--- Draw the selection and leave it in the two marks.
local function drawn(self)
  self:mark_selection()
  self:draw()
end

--- Take the head of the selection to `cell`, which is what extending means once
--- the cell has moved. The anchor comes from nvim while a visual mode is running,
--- so a mapping of the user's that moved the far end is followed.
---@param cell csv.Cell
local function take_head(self, cell)
  self:take_visual()
  self:extend_selection(cell)
  drawn(self)
end

--- `go_to` and `step` end here. In a visual mode the head follows `cell`, and in
--- normal mode the selection is left as it was.
---
--- Entering a visual mode is what picks the cells out, so a move with nothing
--- selected is a cursor move nvim made on its way in, `gv` putting the cursor on a
--- corner before `start_extending` has read that corner.
---@param cell csv.Cell|nil Where the cell landed, absent when it could not move.
local function moved(self, cell)
  if cell and mode.in_visual() and self:has_selection() then
    take_head(self, cell)
  end
end

--- The anchor a fresh selection takes, dropped where the user is standing.
---@param kind csv.SelectionKind
---@return boolean whether there is a selection to extend afterwards
local function anchor_here(self, kind)
  if self:has_selection() then
    return true
  end
  local cell = self:active_cell()
  if not cell then
    return false
  end
  self:select_cells(cell, cell, kind)
  self:mark_selection()
  return true
end

--- Move the active cell to `cell`.
---@param cell csv.Cell|nil
function M.go_to(self, cell)
  moved(self, self:move_to(cell))
end

--- Move the active cell `rows` rows and `columns` columns from where it is.
---@param rows integer
---@param columns integer
function M.step(self, rows, columns)
  moved(self, self:move_by(rows, columns))
end

--- A click in this window is about to move the cursor, and lands exactly where the
--- user pointed rather than a step away from it. A click anywhere else says nothing
--- about the cell, and the flag is dropped on the next tick whatever happens,
--- because a click that lands on the byte the cursor is already parked on moves
--- nothing and never reaches `follow_cursor`.
function M.click(self)
  local position = vim.fn.getmousepos()
  self.clicked = position.winid == self.window and position.line > 0
  vim.schedule(function()
    self.clicked = false
  end)
end

--- Follow the cursor to wherever nvim has left it, which is how a motion this
--- plugin does not map reaches the active cell. A cursor still parked where the
--- plugin left it has not been moved by anyone.
function M.follow_cursor(self)
  local was_click = self.clicked
  self.clicked = false

  if not self:cursor_moved() then
    return
  end
  if was_click then
    return self:go_to(self:physical_cell())
  end
  self:go_to(self:moved_cell())
end

--- Take the selection out by `rows` and `columns`, walking the active cell with
--- it. This is what a shift keyed move runs, so it extends whether or not nvim is
--- in a visual mode.
---@param rows integer
---@param columns integer
function M.extend(self, rows, columns)
  if not anchor_here(self, "cell") then
    return
  end
  local cell = self:move_by(rows, columns)
  if cell then
    take_head(self, cell)
  end
end

--- Take the selection out to `cell`, which is what a shift click means. The active
--- cell lands there too, so the cursor, the highlight and nvim's own far end all
--- reach where the user pointed.
---@param cell csv.Cell
function M.extend_to(self, cell)
  if anchor_here(self, "cell") and self:move_to(cell) then
    take_head(self, cell)
  end
end

--- Entering a visual mode. A selection already picked out keeps its anchor and
--- takes its head to the active cell, so `v` after a run of shift keyed moves goes
--- on from where the user is standing. The kind comes from the mode, because a
--- whole column has no shape nvim's region can hold and `set_visual` is about to
--- hand it over.
---
--- With nothing selected, `getpos("v")` and the cursor become the anchor and the
--- head. `v` puts both on the active cell. `gv` puts them on the corners nvim
--- reselected out of `'<` and `'>`, which hold the cells this module last wrote
--- there, so the old block comes back.
function M.start_extending(self)
  local standing = self:active_cell()
  if self:has_selection() and standing then
    self:extend_selection(standing)
    self:set_kind(kind_of_mode())
    self:set_visual()
    return drawn(self)
  end

  local other = vim.fn.getpos("v")
  local anchor = self.buffer.page:cell_at(other[2], other[3] - 1)
  local head = self:physical_cell()
  if anchor and head then
    self:select_cells(anchor, head, kind_of_mode())
    -- `gv` moves the cursor to a corner, and the active cell has to come along,
    -- because every move from here takes the head with it.
    self:move_to(head)
    drawn(self)
  end
end

--- Switching between visual modes, which is the one thing that changes the kind of
--- a selection already picked out. Pressing `V` partway through means whole rows
--- from here on, the way it does in a buffer of text.
function M.change_kind(self)
  self:set_kind(kind_of_mode())
  drawn(self)
end

--- Swap which end of the selection moves, and take the active cell to it. This is
--- `o`, and it is ours because a selection outlives the visual mode it was made in,
--- where nvim's own `o` has no region left to swap.
function M.swap_ends(self)
  if not self:has_selection() then
    return
  end
  self.anchor, self.head = self.head, self.anchor
  self:move_to(self.buffer.page:cell_of(self.head))
  self:set_visual()
  drawn(self)
end

--- Pick out the block `kind` covers around the active cell, leaving the cell where
--- it is, which is how a whole column and the whole page are picked in one press.
---@param kind csv.SelectionKind
function M.select_kind(self, kind)
  local cell = self:active_cell()
  if not cell then
    return
  end
  self:select_cells(cell, cell, kind)
  drawn(self)
end

--- Drop the selection, leaving the block it was in the two marks, so `gv` brings it
--- back the way it does after leaving visual mode in any other buffer.
function M.deselect(self)
  self:mark_selection()
  self:clear_selection()
  self:draw()
end

return M
