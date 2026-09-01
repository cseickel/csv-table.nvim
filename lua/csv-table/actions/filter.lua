local buffer = require("csv-table.buffer")
local dialog = require("csv-table.dialog")
local selection = require("csv-table.selection")
local state = require("csv-table.state")
local utils = require("csv-table.utils.actions.utils")

local M = {}

---@type table<string, csv.Action>
M.utils.actions = {
  filter_to_marked_rows = utils.action("Show only marked rows, or stop doing so", function(buf)
    state.toggle_marked_filter(buf.state)
    buffer.render(buf)
  end),

  filter_to_marked_columns = utils.action("Show only marked columns, or stop doing so", function(buf)
    selection.toggle_marked_columns(buf.state)
    buffer.render(buf)
  end),

  filter_to_marked_both = utils.action("Show only marked rows and marked columns", function(buf)
    selection.toggle_marked_columns(buf.state)
    state.toggle_marked_filter(buf.state)
    buffer.render(buf)
  end),

  filter = utils.action("Filter on this column", function(buf)
    local column = utils.column_under_cursor(buf)
    if column then
      dialog.open(buf, column)
    end
  end),

  pop_filter = utils.action("Drop the filter added last", function(buf)
    state.pop_filter(buf.state)
    buffer.render(buf)
  end),

  clear_filters = utils.action("Drop every filter", function(buf)
    state.clear_filters(buf.state)
    buffer.render(buf)
  end),
}

return M
