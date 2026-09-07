--[[
Moving the active cell, and what each move does to the selection.

Three things move the cell: an action bound to a key, a motion nvim owns and
this plugin sees afterwards, and a mouse click. All three come through here, so
the rule about the selection is written once.

The rule is that a plain move leaves the selection where the user put it. Only
extending moves the head, and the user extends in two ways: a shift keyed move,
or any move at all while nvim is in a visual mode. Nvim owns that mode, so a
remapped `<C-v>` and any plugin that starts visual mode both count, and this
module never has to be told which key was pressed.

`state.selection` holds the block that `csv-table.overlay` draws, because the
block outlives visual mode: a plain move leaves it alone and the next shift
keyed move extends it, both in normal mode. Every change to it is written to
`'<` and `'>` as well, and entering visual mode with nothing selected reads
those two ends back, which is what makes nvim's own `gv` reselect the cells.
]]

local active_cell = require("csv-table.active_cell")
local layout_module = require("csv-table.layout")
local overlay = require("csv-table.overlay")
local selection = require("csv-table.selection")

local M = {}

--- Whether nvim is in a visual mode, which is what says every move extends.
---@return boolean
local function in_visual_mode()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

--- Leave the selected block in `'<` and `'>` as well, so nvim's own `gv`
--- reselects those cells rather than the two ends nvim was holding. Reading
--- those marks back on the way into visual mode is what makes `gv` ours with no
--- action of its own.
---
--- Nvim writes both marks itself when a visual mode ends, so `buffer.lua` runs
--- this again on the way out and lands last.
---
--- The marks outlive a render, the same way they do in a buffer of text that
--- was replaced: they name a line and a byte, and after a sort those name
--- different rows.
---
--- `nvim_buf_set_mark` refuses `<` and `>`, so `setpos` does the writing, and it
--- writes nothing unless `buf` is the buffer the user is in.
---@param buf csv.Buffer
function M.mark_selection(buf)
  local bounds = selection.bounds(buf.state, buf.layout)
  if not bounds then
    return
  end

  local first = layout_module.cell_ranges(buf.layout, bounds.top)[bounds.left]
  local last = layout_module.cell_ranges(buf.layout, bounds.bottom)[bounds.right]
  if first and last then
    vim.fn.setpos("'<", { buf.bufnr, bounds.top, first.from + 1, 0 })
    vim.fn.setpos("'>", { buf.bufnr, bounds.bottom, last.to, 0 })
  end
end

--- Draw the selection and leave it in the two marks.
---@param buf csv.Buffer
local function drawn(buf)
  M.mark_selection(buf)
  overlay.redraw(buf)
end

--- Take the head of the selection to `cell`, which is what extending means once
--- the cell has moved.
---@param buf csv.Buffer
---@param cell csv.Cell
local function take_head(buf, cell)
  selection.extend(buf.state, cell)
  drawn(buf)
end

--- `go_to` and `step` end here. In a visual mode the head follows `cell`, and
--- in normal mode the selection is left as it was.
---
--- Entering a visual mode is what picks the cells out, so a move with nothing
--- selected is a cursor move nvim made on its way in, `gv` putting the cursor on
--- a corner before `start_extending` has read that corner.
---@param buf csv.Buffer
---@param cell csv.Cell|nil Where the cell landed, absent when it could not move.
local function moved(buf, cell)
  if cell and in_visual_mode() and selection.is_set(buf.state) then
    take_head(buf, cell)
  end
end

--- Move the active cell to `cell`.
---@param buf csv.Buffer
---@param window integer
---@param cell csv.Cell|nil
function M.go_to(buf, window, cell)
  moved(buf, active_cell.move_to(buf, window, cell))
end

--- Move the active cell `rows` rows and `columns` columns from where it is.
---@param buf csv.Buffer
---@param window integer
---@param rows integer
---@param columns integer
function M.step(buf, window, rows, columns)
  moved(buf, active_cell.step(buf, window, rows, columns))
end

--- Whether the click about to be handled is one that moves the cursor in a
--- table, which lands exactly where the user pointed rather than a step away
--- from it.
local clicked = false

--- A click in a table window is about to move the cursor. A click anywhere else
--- says nothing about the cell, and the flag is dropped on the next tick
--- whatever happens, because a click that lands on the byte the cursor is
--- already parked on moves nothing and never reaches `follow_cursor`.
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

  if not buf.layout or not active_cell.cursor_moved(buf, window) then
    return
  end
  if was_click then
    return M.go_to(buf, window, active_cell.cell(buf, window))
  end
  M.go_to(buf, window, active_cell.moved_cell(buf, window))
end

--- The anchor a fresh selection takes, dropped where the user is standing.
---@param buf csv.Buffer
---@param window integer
---@param kind csv.SelectionKind
---@return boolean whether there is a selection to extend afterwards
local function anchor_here(buf, window, kind)
  if selection.is_set(buf.state) then
    return true
  end
  local cell = active_cell.cell(buf, window)
  if not cell then
    return false
  end
  selection.set(buf.state, cell, cell, kind)
  M.mark_selection(buf)
  return true
end

--- Take the selection out by `rows` and `columns`, walking the active cell with
--- it. This is what a shift keyed move runs, so it extends whether or not nvim
--- is in a visual mode.
---@param buf csv.Buffer
---@param window integer
---@param rows integer
---@param columns integer
function M.extend(buf, window, rows, columns)
  if not anchor_here(buf, window, "cell") then
    return
  end
  local cell = active_cell.step(buf, window, rows, columns)
  if cell then
    take_head(buf, cell)
  end
end

--- Take the selection out to `cell` without moving the active cell, which is
--- what a shift click means.
---@param buf csv.Buffer
---@param window integer
---@param cell csv.Cell
function M.extend_to(buf, window, cell)
  if anchor_here(buf, window, "cell") then
    take_head(buf, cell)
  end
end

--- The axes a visual mode bounds. Charwise and blockwise both pick out a block
--- of cells, since a selection is cells rather than the text they are painted
--- in, and `V` is whole rows.
---@return csv.SelectionKind
local function kind_of_mode()
  return vim.fn.mode() == "V" and "row" or "cell"
end

--- Entering a visual mode. An existing selection keeps its anchor, head and
--- kind, and the next move extends it.
---
--- With nothing selected, `getpos("v")` and the cursor become the anchor and
--- the head. `v` puts both on the active cell. `gv` puts them on the corners
--- nvim reselected out of `'<` and `'>`, which hold the cells this module last
--- wrote there, so the old block comes back.
---@param buf csv.Buffer
---@param window integer
function M.start_extending(buf, window)
  if selection.is_set(buf.state) then
    return
  end

  local other = vim.fn.getpos("v")
  local anchor = active_cell.cell_at(buf, other[2], other[3] - 1)
  local head = active_cell.cell(buf, window)
  if anchor and head then
    selection.set(buf.state, anchor, head, kind_of_mode())
    -- `gv` moves the cursor to a corner, and the active cell has to come along,
    -- because every move from here takes the head with it.
    active_cell.move_to(buf, window, head)
    drawn(buf)
  end
end

--- Switching between visual modes, which is the one thing that changes the kind
--- of a selection already picked out. Pressing `V` partway through means whole
--- rows from here on, the way it does in a buffer of text.
---@param buf csv.Buffer
function M.change_kind(buf)
  selection.set_kind(buf.state, kind_of_mode())
  drawn(buf)
end

--- Swap which end of the selection moves, and take the active cell to it. This
--- is `o`, and it is ours because nvim's own `o` moves the cursor to nvim's
--- anchor, which every move in a visual mode would then take the head to.
---@param buf csv.Buffer
---@param window integer
function M.swap_ends(buf, window)
  local picked = buf.state.selection
  if not picked then
    return
  end
  picked.anchor, picked.head = picked.head, picked.anchor
  active_cell.move_to(buf, window, picked.head)
  drawn(buf)
end

--- Pick out the block `kind` covers around the active cell, leaving the cell
--- where it is, which is how a whole column and the whole page are picked in
--- one press.
---@param buf csv.Buffer
---@param window integer
---@param kind csv.SelectionKind
function M.select(buf, window, kind)
  local cell = active_cell.cell(buf, window)
  if not cell then
    return
  end
  selection.set(buf.state, cell, cell, kind)
  drawn(buf)
end

--- Drop the selection. The two marks keep the block, so `gv` brings it back the
--- way it does after leaving visual mode in any other buffer.
---@param buf csv.Buffer
function M.clear_selection(buf)
  selection.clear(buf.state)
  overlay.redraw(buf)
end

return M
