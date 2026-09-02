--[[
The actions that open a panel about the file rather than changing the view.
]]

local cursor = require("csv-table.cursor")
local dialog = require("csv-table.dialog")
local inspect = require("csv-table.inspect")
local panel = require("csv-table.panel")
local utils = require("csv-table.actions.utils")

utils.register_action("show_column", "Summarize this column", function(buf)
  local column = cursor.column_at(buf, 0)
  if column then
    panel.stats(buf, column)
  end
end)

utils.register_action("show_cell", "Show everything this cell holds", function(buf)
  local column = cursor.column_at(buf, 0)
  if column then
    inspect.cell(buf, column)
  end
end)

utils.register_action("show_row", "Show pivoted row values", function(buf)
  inspect.row(buf)
end)

utils.register_action("select_sheet", "Choose which sheet to read", function(buf)
  dialog.sheets(buf)
end)

utils.register_action("show_help", "Search every key and run one", function(buf)
  panel.help(buf)
end)

utils.register_action("show_file_info", "Describe this file and the current view", function(buf)
  panel.info(buf)
end)
