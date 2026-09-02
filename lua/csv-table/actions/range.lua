--[[
The actions that select cells.

Selecting changes nothing about what xan would return, so every action here
paints over the text already in the buffer rather than rendering the page again.
Rendering would in any case drop the selection, which is what `buffer.render`
does deliberately.

Extending moves the cursor as well, the way a spreadsheet moves the active cell,
so the keys that extend a selection are also the keys that walk the table.

cSpell:ignore rowids
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local inspect = require("csv-table.inspect")
local query = require("csv-table.query")
local range = require("csv-table.range")
local selection = require("csv-table.selection")
local utils = require("csv-table.actions.utils")

local EDGE = utils.EDGE

--- Take the selection out by `rows` and `cells`, walking the cursor along with
--- it.
---
--- The end of the selection moves from where the selection ends and the cursor
--- moves from where the cursor is, which are the same cell until a whole row or
--- column is selected. Keeping them apart is what lets a selected row be taken
--- down as a whole row while the cursor stays in the column being read.
---@param rows integer
---@param cells integer
---@return fun(buf: csv.Buffer)
local function extender(rows, cells)
  return function(buf)
    local painted = buf.layout
    local selected = buf.state.range
    local from = selected and selected.cursor or cursor.cell_ref(buf, 0)
    if not painted or not from then
      return
    end

    local delta = { rows = rows, columns = cells, shown = #selection.selected(buf.state) }
    local taken = range.step(from, painted, delta)
    if not taken then
      return query.report("the selection is not on this page")
    end

    cursor.step(buf, 0, rows, cells)
    if selected then
      range.extend(buf.state, taken)
    else
      range.set(buf.state, from, taken)
    end
    buffer.repaint(buf)
  end
end

--- Select the rectangle `corners` names, which is how a whole row, a whole
--- column and the whole page are selected in one press. The cursor stays where
--- it is, since the user is reading the cell it is on.
---@param corners fun(buf: csv.Buffer, painted: csv.Layout): csv.CellRef|nil, csv.CellRef|nil
---@return fun(buf: csv.Buffer)
local function selector(corners)
  return function(buf)
    local painted = buf.layout
    if not painted or painted.first_row > painted.last_row then
      return query.report("there is nothing to select")
    end

    local anchor, far = corners(buf, painted)
    if not anchor or not far or not anchor.row or not far.row then
      return
    end

    range.set(buf.state, anchor, far)
    buffer.repaint(buf)
  end
end

---@param buf csv.Buffer
---@return integer
local function last_column(buf)
  return #selection.selected(buf.state)
end

utils.register_action("select_cell", "Select this cell", function(buf)
  local cell = cursor.cell_ref(buf, 0)
  if not cell then
    return
  end
  range.set(buf.state, cell, cell)
  buffer.repaint(buf)
end)

utils.register_action("select_row", "Select this whole row", selector(function(buf, _)
  local cell = cursor.cell_ref(buf, 0)
  if not cell then
    return nil, nil
  end
  return { row = cell.row, column = 1 }, { row = cell.row, column = last_column(buf) }
end))

utils.register_action("select_column", "Select this whole column", selector(function(buf, painted)
  local cell = cursor.cell_ref(buf, 0)
  if not cell then
    return nil, nil
  end
  return
    { row = painted.rowids[painted.first_row], column = cell.column },
    { row = painted.rowids[painted.last_row], column = cell.column }
end))

utils.register_action("select_page", "Select every cell on this page", selector(function(buf, painted)
  return
    { row = painted.rowids[painted.first_row], column = 1 },
    { row = painted.rowids[painted.last_row], column = last_column(buf) }
end))

utils.register_action("clear_selection", "Select nothing", function(buf)
  range.clear(buf.state)
  buffer.repaint(buf)
end)

utils.register_action("extend_left", "Take the selection one column left", extender(0, -1))
utils.register_action("extend_right", "Take the selection one column right", extender(0, 1))
utils.register_action("extend_up", "Take the selection one row up", extender(-1, 0))
utils.register_action("extend_down", "Take the selection one row down", extender(1, 0))

utils.register_action("extend_to_first_column", "Take the selection to the first column", extender(0, -EDGE))
utils.register_action("extend_to_last_column", "Take the selection to the last column", extender(0, EDGE))
utils.register_action("extend_to_first_row", "Take the selection to the top of the page", extender(-EDGE, 0))
utils.register_action("extend_to_last_row", "Take the selection to the bottom of the page", extender(EDGE, 0))

utils.register_action("copy", "Copy the selected cells, or this one", function(buf)
  inspect.copy(buf)
end)
