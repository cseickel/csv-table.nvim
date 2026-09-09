--[[
Moves the active cell and the head of the selection together.

A plain move leaves the selection where the user put it. A move extends it when
the key was shift keyed, or when nvim is in a visual mode. Nvim owns that mode,
so a remapped `<C-v>` and any plugin that starts visual mode both count, and
nothing here has to be told which key was pressed.
]]

local color = require("csv-table.buffer.color")
local cursor = require("csv-table.buffer.cursor")

local M = {}

---@return boolean
local function in_visual_mode()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

--- Leave the selected block in `'<` and `'>`, so nvim's own `gv` reselects those
--- cells rather than the two ends nvim was holding.
---
--- Nvim writes both marks itself when a visual mode ends, so `csv-table.buffer`
--- runs this again on the way out and lands last.
---
--- The marks outlive a render, the same way they do in a buffer of text that was
--- replaced: they name a line and a byte, and after a sort those name different
--- rows.
---
--- `nvim_buf_set_mark` refuses `<` and `>`, so `setpos` does the writing, and it
--- writes nothing unless `buf` is the buffer the user is in.
---@param buf csv.Buffer
function M.mark_selection(buf)
  local bounds = buf.query:selection_bounds(buf.page)
  if not bounds then
    return
  end

  local first = buf.page:cell_ranges(bounds.top)[bounds.left]
  local last = buf.page:cell_ranges(bounds.bottom)[bounds.right]
  if first and last then
    vim.fn.setpos("'<", { buf.bufnr, bounds.top, first.from + 1, 0 })
    vim.fn.setpos("'>", { buf.bufnr, bounds.bottom, last.to, 0 })
  end
end

--- Draw the selection and leave it in the two marks.
---@param buf csv.Buffer
local function drawn(buf)
  M.mark_selection(buf)
  color.redraw(buf)
end

--- Take the head of the selection to `cell`, which is what extending means once
--- the cell has moved.
---@param buf csv.Buffer
---@param cell csv.Cell
local function take_head(buf, cell)
  buf.query:extend_selection(cell)
  drawn(buf)
end

--- `go_to` and `step` end here. In a visual mode the head follows `cell`, and in
--- normal mode the selection is left as it was.
---
--- Entering a visual mode is what picks the cells out, so a move with nothing
--- selected is a cursor move nvim made on its way in, `gv` putting the cursor on
--- a corner before `start_extending` has read that corner.
---@param buf csv.Buffer
---@param cell csv.Cell|nil Where the cell landed, absent when it could not move.
local function moved(buf, cell)
  if cell and in_visual_mode() and buf.query:has_selection() then
    take_head(buf, cell)
  end
end

--- Move the active cell to `cell`.
---@param buf csv.Buffer
---@param window integer
---@param cell csv.Cell|nil
function M.go_to(buf, window, cell)
  moved(buf, cursor.move_to(buf, window, cell))
end

--- Move the active cell `rows` rows and `columns` columns from where it is.
---@param buf csv.Buffer
---@param window integer
---@param rows integer
---@param columns integer
function M.step(buf, window, rows, columns)
  moved(buf, cursor.step(buf, window, rows, columns))
end

--- Whether the click about to be handled is one that moves the cursor in a table,
--- which lands exactly where the user pointed rather than a step away from it.
local clicked = false

--- A click in a table window is about to move the cursor. A click anywhere else
--- says nothing about the cell, and the flag is dropped on the next tick whatever
--- happens, because a click that lands on the byte the cursor is already parked
--- on moves nothing and never reaches `follow_cursor`.
function M.click()
  local position = vim.fn.getmousepos()
  clicked = position.winid == vim.api.nvim_get_current_win() and position.line > 0
  vim.schedule(function()
    clicked = false
  end)
end

--- Follow the cursor to wherever nvim has left it, which is how a motion this
--- plugin does not map reaches the active cell. A cursor still parked where the
--- plugin left it has not been moved by anyone.
---@param buf csv.Buffer
---@param window integer
function M.follow_cursor(buf, window)
  local was_click = clicked
  clicked = false

  if not cursor.cursor_moved(buf, window) then
    return
  end
  if was_click then
    return M.go_to(buf, window, cursor.physical_cell(buf, window))
  end
  M.go_to(buf, window, cursor.moved_cell(buf, window))
end

--- The anchor a fresh selection takes, dropped where the user is standing.
---@param buf csv.Buffer
---@param window integer
---@param kind csv.SelectionKind
---@return boolean whether there is a selection to extend afterwards
local function anchor_here(buf, window, kind)
  if buf.query:has_selection() then
    return true
  end
  local cell = cursor.active_cell(buf, window)
  if not cell then
    return false
  end
  buf.query:select_cells(cell, cell, kind)
  M.mark_selection(buf)
  return true
end

--- Take the selection out by `rows` and `columns`, walking the active cell with
--- it. This is what a shift keyed move runs, so it extends whether or not nvim is
--- in a visual mode.
---@param buf csv.Buffer
---@param window integer
---@param rows integer
---@param columns integer
function M.extend(buf, window, rows, columns)
  if not anchor_here(buf, window, "cell") then
    return
  end
  local cell = cursor.step(buf, window, rows, columns)
  if cell then
    take_head(buf, cell)
  end
end

--- Take the selection out to `cell` without moving the active cell, which is what
--- a shift click means.
---@param buf csv.Buffer
---@param window integer
---@param cell csv.Cell
function M.extend_to(buf, window, cell)
  if anchor_here(buf, window, "cell") then
    take_head(buf, cell)
  end
end

--- The axes a visual mode bounds. Charwise and blockwise both pick out a block of
--- cells, since a selection is cells rather than the text they are painted in,
--- and `V` is whole rows.
---@return csv.SelectionKind
local function kind_of_mode()
  return vim.fn.mode() == "V" and "row" or "cell"
end

--- Entering a visual mode. An existing selection keeps its anchor, head and kind,
--- and the next move extends it.
---
--- With nothing selected, `getpos("v")` and the cursor become the anchor and the
--- head. `v` puts both on the active cell. `gv` puts them on the corners nvim
--- reselected out of `'<` and `'>`, which hold the cells this module last wrote
--- there, so the old block comes back.
---@param buf csv.Buffer
---@param window integer
function M.start_extending(buf, window)
  if buf.query:has_selection() then
    return
  end

  local other = vim.fn.getpos("v")
  local anchor = buf.page:cell_at(other[2], other[3] - 1)
  local head = cursor.physical_cell(buf, window)
  if anchor and head then
    buf.query:select_cells(anchor, head, kind_of_mode())
    -- `gv` moves the cursor to a corner, and the active cell has to come along,
    -- because every move from here takes the head with it.
    cursor.move_to(buf, window, head)
    drawn(buf)
  end
end

--- Switching between visual modes, which is the one thing that changes the kind
--- of a selection already picked out. Pressing `V` partway through means whole
--- rows from here on, the way it does in a buffer of text.
---@param buf csv.Buffer
function M.change_kind(buf)
  buf.query:set_selection_kind(kind_of_mode())
  drawn(buf)
end

--- Swap which end of the selection moves, and take the active cell to it. This is
--- `o`, and it is ours because nvim's own `o` moves the cursor to nvim's anchor,
--- which every move in a visual mode would then take the head to.
---@param buf csv.Buffer
---@param window integer
function M.swap_ends(buf, window)
  local picked = buf.query.selection
  if not picked then
    return
  end
  picked.anchor, picked.head = picked.head, picked.anchor
  cursor.move_to(buf, window, picked.head)
  drawn(buf)
end

--- Pick out the block `kind` covers around the active cell, leaving the cell where
--- it is, which is how a whole column and the whole page are picked in one press.
---@param buf csv.Buffer
---@param window integer
---@param kind csv.SelectionKind
function M.select(buf, window, kind)
  local cell = cursor.active_cell(buf, window)
  if not cell then
    return
  end
  buf.query:select_cells(cell, cell, kind)
  drawn(buf)
end

--- Drop the selection. The two marks keep the block, so `gv` brings it back the
--- way it does after leaving visual mode in any other buffer.
---@param buf csv.Buffer
function M.clear_selection(buf)
  buf.query:clear_selection()
  color.redraw(buf)
end

return M
