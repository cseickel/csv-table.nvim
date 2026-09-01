--[[
The actions that order the rows.

One key sorts by a column alone and another adds it as a less significant key,
so the same column can be asked for twice and mean two different things.
]]

local buffer = require("csv-table.buffer")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

---@param direction "asc"|"desc"
---@return fun(buf: csv.Buffer)
local function sorter(direction)
  return function(buf)
    utils.on_column(buf, function(column)
      state.sort_by(buf.state, column, direction)
    end)
  end
end

---@param direction "asc"|"desc"
---@return fun(buf: csv.Buffer)
local function keyer(direction)
  return function(buf)
    utils.on_column(buf, function(column)
      state.add_sort_key(buf.state, column, direction)
    end)
  end
end

utils.register_action("sort_asc", "Sort by this column ascending, or clear that sort", sorter("asc"))
utils.register_action("sort_desc", "Sort by this column descending, or clear that sort", sorter("desc"))
utils.register_action("add_sort_key_asc", "Add this column to the sort, ascending", keyer("asc"))
utils.register_action("add_sort_key_desc", "Add this column to the sort, descending", keyer("desc"))

utils.register_action("remove_sort_key", "Drop this column from the sort", function(buf)
  utils.on_column(buf, function(column)
    state.remove_sort_key(buf.state, column)
  end)
end)

utils.register_action("clear_sort", "Clear the sort entirely", function(buf)
  state.clear_sort(buf.state)
  buffer.render(buf)
end)
