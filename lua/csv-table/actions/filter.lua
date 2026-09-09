--[[
Registers the actions that narrow what is shown.

Filters are ANDed, and each one names a column except the marked filter, which
reads the marked set at render time, so marking another row widens the view at once.
]]

local dialog = require("csv-table.popup.dialog")
local utils = require("csv-table.actions.utils")

utils.register_action(
  "filter_to_marked_rows",
  "Show only marked rows, or stop doing so",
  function(view)
    view.buffer.query:toggle_marked_filter()
    view.buffer:render()
  end
)

utils.register_action(
  "filter_to_marked_columns",
  "Show only marked columns, or stop doing so",
  function(view)
    view.buffer.query:show_marked_columns_only()
    view.buffer:render()
  end
)

utils.register_action(
  "filter_to_marked_both",
  "Show only marked rows and marked columns",
  function(view)
    view.buffer.query:show_marked_columns_only()
    view.buffer.query:toggle_marked_filter()
    view.buffer:render()
  end
)

utils.register_action("filter", "Filter on this column", function(view)
  local column = view:column()
  if column then
    dialog.open(view, column)
  end
end)

utils.register_action("pop_filter", "Drop the filter added last", function(view)
  view.buffer.query:pop_filter()
  view.buffer:render()
end)

utils.register_action("clear_filters", "Drop every filter", function(view)
  view.buffer.query:clear_filters()
  view.buffer:render()
end)
