--[[
Registers the actions that order the rows.

Sorting by a column and adding it as a less significant key are separate keys, so
the same column asked for twice means two different things.
]]

local utils = require("csv-table.actions.utils")

---@param direction "asc"|"desc"
---@return fun(view: csv.View)
local function sort_action(direction)
  return function(view)
    utils.on_column(view, function(column)
      view.buffer.query:sort_by(column, direction)
    end)
  end
end

---@param direction "asc"|"desc"
---@return fun(view: csv.View)
local function add_sort_key_action(direction)
  return function(view)
    utils.on_column(view, function(column)
      view.buffer.query:add_sort_key(column, direction)
    end)
  end
end

utils.register_action(
  "sort_asc",
  "Sort by this column ascending, or clear that sort",
  sort_action("asc")
)
utils.register_action(
  "sort_desc",
  "Sort by this column descending, or clear that sort",
  sort_action("desc")
)
utils.register_action(
  "add_sort_key_asc",
  "Add this column to the sort, ascending",
  add_sort_key_action("asc")
)
utils.register_action(
  "add_sort_key_desc",
  "Add this column to the sort, descending",
  add_sort_key_action("desc")
)

utils.register_action("remove_sort_key", "Drop this column from the sort", function(view)
  utils.on_column(view, function(column)
    view.buffer.query:remove_sort_key(column)
  end)
end)

utils.register_action("clear_sort", "Clear the sort entirely", function(view)
  view.buffer.query:clear_sort()
  view.buffer:render()
end)
