local buffer = require("csv-table.buffer")
local column = require("csv-table.actions.column")
local filter = require("csv-table.actions.filter")
local info = require("csv-table.actions.info")
local page = require("csv-table.actions.page")
local range = require("csv-table.actions.range")
local sort = require("csv-table.actions.sort")
local utils = require("csv-table.actions.utils")

local state = require("csv-table.state")

local M = {
  refresh = utils.action("Read the file again", function(buf)
    buffer.render(buf)
  end),

  clear_all = utils.action("Clear filters, sort, marks and hidden columns", function(buf)
    state.reset(buf.state)
    buffer.render(buf)
  end),
}

-- The actions defined elsewhere, so a key finds every action in one table. A
-- name defined twice would leave which one runs to the order of a Lua table, so
-- it stops the plugin loading instead.
for _, defined in ipairs({
  column,
  filter,
  info,
  page,
  range,
  sort,
}) do
  for name, described in pairs(defined) do
    if M.actions[name] then
      error("csv-table: two actions are named " .. name)
    end
    M.actions[name] = described
  end
end

return M
