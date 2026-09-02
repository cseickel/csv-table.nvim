--[[
The actions that narrow which rows are shown.

Filters are ANDed, and each one names a column except the marked filter, which
reads the marked set at render time so marking another row widens the view at
once.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local dialog = require("csv-table.dialog")
local selection = require("csv-table.selection")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

utils.register_action("filter_to_marked_rows", "Show only marked rows, or stop doing so", function(buf)
  state.toggle_marked_filter(buf.state)
  buffer.render(buf)
end)

utils.register_action("filter_to_marked_columns", "Show only marked columns, or stop doing so", function(buf)
  selection.toggle_marked_columns(buf.state)
  buffer.render(buf)
end)

utils.register_action("filter_to_marked_both", "Show only marked rows and marked columns", function(buf)
  selection.toggle_marked_columns(buf.state)
  state.toggle_marked_filter(buf.state)
  buffer.render(buf)
end)

utils.register_action("filter", "Filter on this column", function(buf)
  local column = cursor.column_at(buf, 0)
  if column then
    dialog.open(buf, column)
  end
end)

utils.register_action("pop_filter", "Drop the filter added last", function(buf)
  state.pop_filter(buf.state)
  buffer.render(buf)
end)

utils.register_action("clear_filters", "Drop every filter", function(buf)
  state.clear_filters(buf.state)
  buffer.render(buf)
end)
