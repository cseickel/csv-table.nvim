--[[
The `csv.View` methods that move the active cell and the head of the selection
together.

A plain move leaves the selection alone. A move extends it when the key was shift
keyed or when nvim is in a visual mode. nvim owns visual mode, so a remapped
`<C-v>` and any plugin that starts visual mode both count, and nothing here has
to be told which key was pressed.
]]

local mode = require("csv-table.utils.mode")

local M = {}

--- The axes the current visual mode bounds. Charwise and blockwise both pick out
--- a block of cells, and `V` is whole rows.
---@return csv.SelectionKind
local function kind_of_mode()
  return vim.fn.mode() == "V" and "row" or "cell"
end

local function redraw(self)
  self:mark_selection()
  self:draw()
end

--- Move the head of the selection to `cell`. The anchor is read back from nvim
--- first, so a mapping of the user's that moved the far end is followed.
---@param cell csv.Cell
local function take_head(self, cell)
  self:take_visual()
  self:extend_selection(cell)
  redraw(self)
end

--- In a visual mode the head follows `cell`; in normal mode the selection is left
--- alone. A move in visual mode with nothing selected is nvim putting the cursor
--- on a corner on its way in, `gv` before `start_extending` has read that corner,
--- and is left alone too.
---@param cell csv.Cell|nil Where the cell landed, absent when it could not move.
local function after_move(self, cell)
  if cell and mode.in_visual() and self:has_selection() then
    take_head(self, cell)
  end
end

--- Start a selection of `kind` on the active cell when there is none.
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
  after_move(self, self:move_to(cell))
end

--- Move the active cell `rows` rows and `columns` columns from where it is.
---@param rows integer
---@param columns integer
function M.step(self, rows, columns)
  after_move(self, self:move_by(rows, columns))
end

--- A click in this window is about to move the cursor, and lands on the cell it
--- pointed at rather than a step away. A click in any other window says nothing
--- about the cell. The flag is dropped on the next tick whatever happens, because
--- a click on the byte the cursor is already parked on moves nothing and never
--- reaches `follow_cursor`.
function M.click(self)
  local position = vim.fn.getmousepos()
  self.clicked = position.winid == self.window and position.line > 0
  vim.schedule(function()
    self.clicked = false
  end)
end

--- Move the active cell to wherever nvim left the cursor, which is how a motion
--- this plugin does not map reaches it. A cursor still on the byte it was parked
--- on has not moved.
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

--- Extend the selection by `rows` and `columns`, moving the active cell with it,
--- whether or not nvim is in a visual mode.
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

--- Extend the selection to `cell`. The active cell lands there too, so the cursor,
--- the highlight and nvim's own far end all reach it.
---@param cell csv.Cell
function M.extend_to(self, cell)
  if anchor_here(self, "cell") and self:move_to(cell) then
    take_head(self, cell)
  end
end

--- Entering a visual mode. A selection already made keeps its anchor and moves its
--- head to the active cell, so `v` after a run of shift keyed moves continues it.
--- The kind comes from the mode, because a whole column has no shape nvim's
--- region can hold and `set_visual` is about to hand the region over.
---
--- With nothing selected, `getpos("v")` and the cursor become the anchor and the
--- head. `v` puts both on the active cell. `gv` puts them on the corners nvim
--- reselected out of `'<` and `'>`, which hold the cells `mark_selection` last
--- wrote there.
function M.start_extending(self)
  local active_cell = self:active_cell()
  if self:has_selection() and active_cell then
    self:extend_selection(active_cell)
    self:set_kind(kind_of_mode())
    self:set_visual()
    return redraw(self)
  end

  local anchor_position = vim.fn.getpos("v")
  local anchor = self.buffer.page:cell_at(anchor_position[2], anchor_position[3] - 1)
  local head = self:physical_cell()
  if anchor and head then
    self:select_cells(anchor, head, kind_of_mode())
    -- `gv` moves the cursor to a corner, and the active cell has to come along.
    self:move_to(head)
    redraw(self)
  end
end

--- Switching between visual modes. `V` partway through a selection means whole
--- rows from here on.
function M.change_kind(self)
  self:set_kind(kind_of_mode())
  redraw(self)
end

--- Swap which end of the selection moves and put the active cell on it. This is the
--- plugin's own `o`, because a selection outlives the visual mode it was made in,
--- where nvim's `o` has no region left to swap.
function M.swap_ends(self)
  if not self:has_selection() then
    return
  end
  self.anchor, self.head = self.head, self.anchor
  self:move_to(self.buffer.page:cell_of(self.head))
  self:set_visual()
  redraw(self)
end

--- Select the block `kind` makes of the active cell, leaving the cell where it is.
---@param kind csv.SelectionKind
function M.select_kind(self, kind)
  local cell = self:active_cell()
  if not cell then
    return
  end
  self:select_cells(cell, cell, kind)
  redraw(self)
end

--- Drop the selection, leaving the block in `'<` and `'>` so `gv` brings it back.
function M.deselect(self)
  self:mark_selection()
  self:clear_selection()
  self:draw()
end

return M
