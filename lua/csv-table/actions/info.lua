--[[
Registers the actions that open a popup rather than changing the view.
]]

local dialog = require("csv-table.popup.dialog")
local panel = require("csv-table.popup.panel")
local show = require("csv-table.popup.show")
local utils = require("csv-table.actions.utils")

utils.register_action("show_column", "Summarize this column", function(view)
  local column = view:column()
  if column then
    panel.stats(view, column)
  end
end)

utils.register_action("show_cell", "Show everything this cell holds", function(view)
  show.cell(view)
end)

utils.register_action("show_row", "Show pivoted row values", function(view)
  show.row(view)
end)

utils.register_action("select_sheet", "Choose which sheet to read", function(view)
  dialog.sheets(view)
end)

utils.register_action("show_help", "Search every key and run one", function(view)
  panel.help(view)
end)

utils.register_action("show_file_info", "Describe this file and the current view", function(view)
  panel.info(view)
end)
