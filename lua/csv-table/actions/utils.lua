--[[
Holds the registry every action is written into.

A name registered twice stops the plugin loading, since which of the two a key
would run is otherwise the order of a Lua table.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.buffer.cursor")

local M = {}

--- Further than any table is wide or long, so a step of this many rows or cells
--- reaches the edge without a second way of naming one.
M.EDGE = 1000000

---@class csv.Action
---@field description string
---@field run fun(buf: csv.Buffer)

---@type table<string, csv.Action>
local actions = {}

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

--- Run `change` against the active cell's column, then render. The first render
--- is what puts a cell there, so this waits for it.
---@param buf csv.Buffer
---@param change fun(column: csv.Column)
function M.on_column(buf, change)
  local column = cursor.column(buf, 0)
  if not column then
    return
  end
  change(column)
  buffer.render(buf)
end

return M
