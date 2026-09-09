--[[
Registers the actions that narrow what is shown.

Filters are ANDed, and each one names a column except the marked filter, which
reads the marked set at render time, so marking another row widens the view at
once.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.buffer.cursor")
local dialog = require("csv-table.popup.dialog")
local utils = require("csv-table.actions.utils")

utils.register_action("filter_to_marked_rows", "Show only marked rows, or stop doing so", function(buf)
  buf.query:toggle_marked_filter()
  buffer.render(buf)
end)

utils.register_action(
  "filter_to_marked_columns",
  "Show only marked columns, or stop doing so",
  function(buf)
    buf.query:show_marked_columns_only()
    buffer.render(buf)
  end
)

utils.register_action("filter_to_marked_both", "Show only marked rows and marked columns", function(buf)
  buf.query:show_marked_columns_only()
  buf.query:toggle_marked_filter()
  buffer.render(buf)
end)

utils.register_action("filter", "Filter on this column", function(buf)
  local column = cursor.column(buf, 0)
  if column then
    dialog.open(buf, column)
  end
end)

utils.register_action("pop_filter", "Drop the filter added last", function(buf)
  buf.query:pop_filter()
  buffer.render(buf)
end)

utils.register_action("clear_filters", "Drop every filter", function(buf)
  buf.query:clear_filters()
  buffer.render(buf)
end)
