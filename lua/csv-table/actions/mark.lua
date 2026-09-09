--[[
Registers the mark actions.

A row is marked by its source id rather than by the line it is drawn on, so a
mark survives sorting, filtering and turning the page.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.buffer.cursor")
local utils = require("csv-table.actions.utils")

utils.register_action("toggle_mark_row", "Mark or unmark this row", function(buf)
  local cell = cursor.cell(buf, 0)
  if not cell then
    return
  end
  buf.query:toggle_mark(cell.row.row_id)
  buffer.render(buf)
end)

utils.register_action("toggle_mark_column", "Mark or unmark this column", function(buf)
  utils.on_column(buf, function(column)
    buf.query:toggle_mark_column(column)
  end)
end)

utils.register_action("clear_marks", "Clear every marked row and column", function(buf)
  buf.query:clear_marks()
  buf.query:clear_marked_columns()
  buffer.render(buf)
end)
