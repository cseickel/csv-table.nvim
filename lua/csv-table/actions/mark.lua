--[[
Registers the mark actions.

A row is marked by its source id rather than by the line it is drawn on, so a mark
survives sorting, filtering and turning the page.
]]

local utils = require("csv-table.actions.utils")

utils.register_action("toggle_mark_row", "Mark or unmark this row", function(view)
  local cell = view:active_cell()
  if not cell then
    return
  end
  view.buffer.query:toggle_mark(cell.row.row_id)
  view.buffer:render()
end)

utils.register_action("toggle_mark_column", "Mark or unmark this column", function(view)
  utils.on_column(view, function(column)
    view.buffer.query:toggle_mark_column(column)
  end)
end)

utils.register_action("clear_marks", "Clear every marked row and column", function(view)
  view.buffer.query:clear_marks()
  view.buffer.query:clear_marked_columns()
  view.buffer:render()
end)
