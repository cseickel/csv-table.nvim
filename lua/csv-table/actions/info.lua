--[[
Everything a key can do.

Each utils.action carries the sentence that describes it, so the help panel is
generated from this table and cannot drift from the bindings. An utils.action reads
whatever it needs from the cursor, changes the state, and asks for a repaint.

The utils.actions that act on a column live in `csv-table.column_actions` and the ones
that select cells in `csv-table.range_utils.actions`. Both are merged in here, so a key
still finds every utils.action in one table.
]]

local dialog = require("csv-table.dialog")
local inspect = require("csv-table.inspect")
local panel = require("csv-table.panel")
local utils = require("csv-table.utils.utils.actions.utils")

local M = {}

---@type table<string, csv.Action>
M.utils.actions = {
  show_stats = utils.action("Summarize this column", function(buf)
    local column = utils.column_under_cursor(buf)
    if column then
      panel.stats(buf, column)
    end
  end),

  show_cell = utils.action("Show everything this cell holds", function(buf)
    local column = utils.column_under_cursor(buf)
    if column then
      inspect.cell(buf, column)
    end
  end),

  show_row = utils.action("Search this row and copy a value", function(buf)
    inspect.row(buf)
  end),

  show_sheets = utils.action("Choose which sheet to read", function(buf)
    dialog.sheets(buf)
  end),

  show_help = utils.action("Search every key and run one", function(buf)
    panel.help(buf)
  end),

  show_info = utils.action("Describe this file and the current view", function(buf)
    panel.info(buf)
  end),
}

return M
