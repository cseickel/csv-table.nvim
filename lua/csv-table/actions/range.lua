--[[
The actions that select cells.

Selecting changes nothing about what xan would return, so every action here
draws over the text already in the buffer rather than rendering the page again.
Rendering would in any case drop the selection, which is what `buffer.render`
does deliberately.

Extending moves the cursor as well, the way a spreadsheet moves the active cell,
so the keys that extend a selection are also the keys that walk the table.

cSpell:ignore rowids
]]

local buffer = require("csv-table.buffer")
local active_cell = require("csv-table.active_cell")
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
    local current_range = buf.state.range
    local start_cell = current_range and current_range.end or active_cell.cell_ref(buf, 0)
    if not buf.layout or not start_cell then
      return
    end

    local delta = {
      rows = rows,
      columns = cells,
      column_count = #selection.display_columns(buf.state),
    }
    local new_end = range.step(start_cell, buf.layout, delta)
    if not new_end then
      return query.report("the selection is not on this page")
    end

    active_cell.step(buf, 0, rows, cells)
    if current_range then
      range.extend(buf.state, new_end)
    else
      range.set(buf.state, start_cell, new_end)
    end
    buffer.redraw(buf)
  end
end

--- Select the rectangle `corners` names, which is how a whole row, a whole
--- column and the whole page are selected in one press. The cursor stays where
--- it is, since the user is reading the cell it is on.
---@param corners fun(buf: csv.Buffer, layout: csv.Layout): csv.CellRef|nil, csv.CellRef|nil
---@return fun(buf: csv.Buffer)
local function selector(corners)
  return function(buf)
    if not buf.layout or buf.layout.first_row > buf.layout.last_row then
      return query.report("there is nothing to select")
    end

    local anchor, end_cell = corners(buf, buf.layout)
    if not anchor or not end_cell or not anchor.row or not end_cell.row then
      return
    end

    range.set(buf.state, anchor, end_cell)
    buffer.redraw(buf)
  end
end

---@param buf csv.Buffer
---@return integer
local function last_column(buf)
  return #selection.display_columns(buf.state)
end

utils.register_action("select_cell", "Select this cell", function(buf)
  local cell = active_cell.cell_ref(buf, 0)
  if not cell then
    return
  end
  range.set(buf.state, cell, cell)
  buffer.redraw(buf)
end)

utils.register_action("select_row", "Select this whole row", selector(function(buf, _)
  local cell = active_cell.cell_ref(buf, 0)
  if not cell then
    return nil, nil
  end
  return { row = cell.row, column = 1 }, { row = cell.row, column = last_column(buf) }
end))

utils.register_action("select_column", "Select this whole column", selector(function(buf, layout)
  local cell = active_cell.cell_ref(buf, 0)
  if not cell then
    return nil, nil
  end
  return
    { row = layout.row_id_by_index[layout.first_row], column = cell.column },
    { row = layout.row_id_by_index[layout.last_row], column = cell.column }
end))

utils.register_action("select_page", "Select every cell on this page", selector(function(buf, layout)
  return
    { row = layout.row_id_by_index[layout.first_row], column = 1 },
    { row = layout.row_id_by_index[layout.last_row], column = last_column(buf) }
end))

utils.register_action("clear_selection", "Select nothing", function(buf)
  range.clear(buf.state)
  buffer.redraw(buf)
end)

utils.register_action("extend_left", "Take the selection one column left", extender(0, -1))
utils.register_action("extend_right", "Take the selection one column right", extender(0, 1))
utils.register_action("extend_up", "Take the selection one row up", extender(-1, 0))
utils.register_action("extend_down", "Take the selection one row down", extender(1, 0))

utils.register_action("extend_to_first_column", "Take the selection to the first column", extender(0, -EDGE))
utils.register_action("extend_to_last_column", "Take the selection to the last column", extender(0, EDGE))
utils.register_action("extend_to_first_row", "Take the selection to the top of the page", extender(-EDGE, 0))
utils.register_action("extend_to_last_row", "Take the selection to the bottom of the page", extender(EDGE, 0))

utils.register_action("copy", "Copy the selected cells under their column names", function(buf)
  inspect.copy(buf, true)
end)

utils.register_action("copy_without_headers", "Copy the selected cells alone", function(buf)
  inspect.copy(buf, false)
end)
