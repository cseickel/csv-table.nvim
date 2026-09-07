--[[
The actions that select cells.

Selecting leaves the xan output alone, so every action here draws over the text
already in the buffer, and the selection lives as long as that text does.

Extending moves the active cell as well, the way a spreadsheet does, so the keys
that extend a selection are also the keys that walk the table.
]]

local buffer = require("csv-table.buffer")
local active_cell = require("csv-table.active_cell")
local inspect = require("csv-table.inspect")
local layout_module = require("csv-table.layout")
local query = require("csv-table.query")
local selection = require("csv-table.selection")
local utils = require("csv-table.actions.utils")

local EDGE = utils.EDGE

--- Take the selection out by `rows` and `cells`, walking the active cell along
--- with it.
---
--- The head of the selection moves from the head and the active cell moves from
--- where it is, which are the same cell until a whole row or column is selected.
--- Keeping them apart is what lets a selected row be taken down as a whole row
--- while the active cell stays in the column being read.
---@param rows integer
---@param cells integer
---@return fun(buf: csv.Buffer)
local function extender(rows, cells)
  return function(buf)
    local current = buf.state.selection
    local start_cell = current and current.head or active_cell.cell(buf, 0)
    if not buf.layout or not start_cell then
      return
    end

    local delta = { rows = rows, columns = cells }
    local new_head = layout_module.step_cell(buf.layout, start_cell, delta)
    if not new_head then
      return query.report("the selection is not on this page")
    end

    active_cell.step(buf, 0, rows, cells)
    if current then
      selection.extend(buf.state, new_head)
    else
      selection.set(buf.state, start_cell, new_head)
    end
    buffer.redraw(buf)
  end
end

--- Select the rectangle `corners` names, which is how a whole row, a whole
--- column and the whole page are selected in one press. The active cell stays
--- where it is, since the user is reading the cell they are on.
---@param corners fun(buf: csv.Buffer, layout: csv.Layout): csv.Cell|nil, csv.Cell|nil
---@return fun(buf: csv.Buffer)
local function selector(corners)
  return function(buf)
    if not buf.layout or buf.layout.first_line > buf.layout.last_line then
      return query.report("there is nothing to select")
    end

    local anchor, head = corners(buf, buf.layout)
    if not anchor or not head then
      return
    end

    selection.set(buf.state, anchor, head)
    buffer.redraw(buf)
  end
end

---@param layout csv.Layout
---@param row csv.Row
---@param column_number integer
---@return csv.Cell|nil
local function cell_at(layout, row, column_number)
  local column = layout_module.column_at(layout, column_number)
  return column and { row = row, column = column } or nil
end

utils.register_action("select_cell", "Select this cell", function(buf)
  local cell = active_cell.cell(buf, 0)
  if not cell then
    return
  end
  selection.set(buf.state, cell, cell)
  buffer.redraw(buf)
end)

utils.register_action("select_row", "Select this whole row", selector(function(buf, layout)
  local cell = active_cell.cell(buf, 0)
  if not cell then
    return nil, nil
  end
  return
    cell_at(layout, cell.row, 1),
    cell_at(layout, cell.row, layout_module.column_count(layout))
end))

utils.register_action("select_column", "Select this whole column", selector(function(buf, layout)
  local cell = active_cell.cell(buf, 0)
  if not cell then
    return nil, nil
  end
  return
    { row = layout_module.row_at_line(layout, layout.first_line), column = cell.column },
    { row = layout_module.row_at_line(layout, layout.last_line), column = cell.column }
end))

utils.register_action("select_page", "Select every cell on this page", selector(function(buf, layout)
  return
    cell_at(layout, layout_module.row_at_line(layout, layout.first_line), 1),
    cell_at(layout, layout_module.row_at_line(layout, layout.last_line), layout_module.column_count(layout))
end))

utils.register_action("clear_selection", "Select nothing", function(buf)
  selection.clear(buf.state)
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
