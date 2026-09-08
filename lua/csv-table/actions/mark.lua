--[[
Registers toggle_mark_row, toggle_mark_column and clear_marks.

A row is marked by its source id rather than by the line it is drawn on, so a
mark survives sorting, filtering and turning the page.
]]

local buffer = require("csv-table.buffer")
local active_cell = require("csv-table.active_cell")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

utils.register_action("toggle_mark_row", "Mark or unmark this row", function(buf)
  local cell = active_cell.cell(buf, 0)
  if not cell then
    return
  end
  state.toggle_mark(buf.state, cell.row.row_id)
  buffer.render(buf)
end)

utils.register_action("toggle_mark_column", "Mark or unmark this column", function(buf)
  utils.on_column(buf, function(column)
    state.toggle_mark_column(buf.state, column)
  end)
end)

utils.register_action("clear_marks", "Clear every marked row and column", function(buf)
  state.clear_marks(buf.state)
  state.clear_marked_columns(buf.state)
  buffer.render(buf)
end)
