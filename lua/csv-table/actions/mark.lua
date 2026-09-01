--[[
The actions that mark rows and columns.

A row is marked by its source id rather than by the line it is drawn on, so a
mark survives sorting, filtering and turning the page.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

utils.register_action("toggle_mark_row", "Mark or unmark this row", function(buf)
  local rowid = cursor.rowid_at(buf, 0)
  if not rowid then
    return
  end
  state.toggle_mark(buf.state, rowid)
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
