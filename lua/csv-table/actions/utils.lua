--[[
The registry every action is written into, and what the action modules share.

An action module registers its actions as it loads, so `csv-table.actions` reads
this table rather than collecting anything. A name registered twice stops the
plugin loading, because which of the two a key would run is otherwise the order
of a Lua table.

The two helpers resolve a column from the cursor, which most actions do before
the change they make. A helper only one module calls belongs in that module.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local query = require("csv-table.query")

---@class csv.Action
---@field description string
---@field run fun(buf: csv.Buffer)

---@type table<string, csv.Action>
local actions = {}

local M = {}

---@param name string
---@param description string
---@param run fun(buf: csv.Buffer)
function M.register_action(name, description, run)
  if actions[name] then
    error("csv-table: two actions are named " .. name)
  end
  actions[name] = { description = description, run = run }
end

---@param name string
---@return csv.Action|nil
function M.get_action(name)
  return actions[name]
end

---@return table<string, csv.Action>
function M.get_all_actions()
  return actions
end

--- The column under the cursor, or nothing and a word about why. The row id and
--- the borders are not columns, so a key pressed over either has nothing to act
--- on and says so rather than appearing dead.
---@param buf csv.Buffer
---@return csv.Column|nil
function M.column_under_cursor(buf)
  local column = cursor.column_at(buf, 0)
  if not column then
    query.report("the cursor is not on a column")
  end
  return column
end

--- Run `change` against the column under the cursor, then repaint.
---@param buf csv.Buffer
---@param change fun(column: csv.Column)
function M.on_column(buf, change)
  local column = M.column_under_cursor(buf)
  if not column then
    return
  end
  change(column)
  buffer.render(buf)
end

return M
