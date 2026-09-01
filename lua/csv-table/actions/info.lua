--[[
The actions that open a panel about the file rather than changing the view.
]]

local dialog = require("csv-table.dialog")
local inspect = require("csv-table.inspect")
local panel = require("csv-table.panel")
local utils = require("csv-table.actions.utils")

utils.register_action("show_stats", "Summarise this column", function(buf)
  local column = utils.column_under_cursor(buf)
  if column then
    panel.stats(buf, column)
  end
end)

utils.register_action("show_cell", "Show everything this cell holds", function(buf)
  local column = utils.column_under_cursor(buf)
  if column then
    inspect.cell(buf, column)
  end
end)

utils.register_action("show_row", "Search this row and copy a value", function(buf)
  inspect.row(buf)
end)

utils.register_action("show_sheets", "Choose which sheet to read", function(buf)
  dialog.sheets(buf)
end)

utils.register_action("show_help", "Search every key and run one", function(buf)
  panel.help(buf)
end)

utils.register_action("show_info", "Describe this file and the current view", function(buf)
  panel.info(buf)
end)
