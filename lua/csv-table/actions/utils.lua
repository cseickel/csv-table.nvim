--[[
The registry every action is written into.

A name registered twice stops the plugin loading. Otherwise which of the two a
key runs would be whichever a Lua table happened to keep.
]]

local M = {}

--- Further than any table is wide or long. A step of this many rows or cells
--- reaches the edge, so no action needs a separate way of asking for the edge.
M.EDGE = 1000000

---@class csv.Action
---@field description string
---@field run fun(view: csv.View)

---@type table<string, csv.Action>
local actions = {}

---@param name string
---@param description string
---@param run fun(view: csv.View)
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

--- Run `change` on the active cell's column, then render. Before the first render
--- there is no active cell and nothing happens.
---@param view csv.View
---@param change fun(column: csv.Column)
function M.on_column(view, change)
  local column = view:column()
  if not column then
    return
  end
  change(column)
  view.buffer:render()
end

return M
