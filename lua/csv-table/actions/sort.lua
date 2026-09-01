local buffer = require("csv-table.buffer")
local state = require("csv-table.state")
local utils = require("csv-table.utils.utils.actions.utils")

local M = {}

---@param direction "asc"|"desc"
---@return fun(buf: csv.Buffer)
local function set_sort(direction)
  return function(buf)
    utils.on_column(buf, function(column)
      state.sort_by(buf.state, column, direction)
    end)
  end
end

---@param direction "asc"|"desc"
---@return fun(buf: csv.Buffer)
local function add_sort(direction)
  return function(buf)
    utils.on_column(buf, function(column)
      state.add_sort_key(buf.state, column, direction)
    end)
  end
end

---@type table<string, csv.Action>
M.utils.actions = {
  sort_asc = utils.action("Sort by this column ascending, or clear that sort", set_sort("asc")),
  sort_desc = utils.action("Sort by this column descending, or clear that sort", set_sort("desc")),
  add_sort_key_asc = utils.action("Add this column to the sort, ascending", add_sort("asc")),
  add_sort_key_desc = utils.action("Add this column to the sort, descending", add_sort("desc")),

  remove_sort_key = utils.action("Drop this column from the sort", function(buf)
    utils.on_column(buf, function(column)
      state.remove_sort_key(buf.state, column)
    end)
  end),

  clear_sort = utils.action("Clear the sort entirely", function(buf)
    state.clear_sort(buf.state)
    buffer.render(buf)
  end),
}

return M
