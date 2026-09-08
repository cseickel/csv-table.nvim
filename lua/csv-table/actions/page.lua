--[[
Registers the actions that move between pages: next_page, prev_page,
first_page, last_page and set_page_size.

`state.row_count` says where the last page is, and `buffer.render` fills it in
after each render, so these turn a page without going to xan first. A render
that lands past the end steps back on its own, which covers the moment before
the first count arrives.
]]

local buffer = require("csv-table.buffer")
local query = require("csv-table.query")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

--- The 0-based number of the last page, once the rows have been counted.
---@param buf csv.Buffer
---@return integer|nil
local function last_page(buf)
  local total = buf.state.row_count
  return total and math.max(math.ceil(total / buf.state.limit) - 1, 0) or nil
end

utils.register_action("next_page", "Show the next page", function(buf)
  local last = last_page(buf)
  if last and buf.state.page >= last then
    return vim.notify("csv-table: last page", vim.log.levels.INFO)
  end
  state.turn_page(buf.state, 1)
  buffer.render(buf)
end)

utils.register_action("prev_page", "Show the previous page", function(buf)
  state.turn_page(buf.state, -1)
  buffer.render(buf)
end)

utils.register_action("first_page", "Show the first page", function(buf)
  state.goto_page(buf.state, 0)
  buffer.render(buf)
end)

utils.register_action("last_page", "Show the last page", function(buf)
  local last = last_page(buf)
  if last then
    state.goto_page(buf.state, last)
    return buffer.render(buf)
  end

  query.count(buf.state, query.report, function(count)
    buf.state.row_count = count
    state.goto_page(buf.state, math.max(math.ceil(count / buf.state.limit) - 1, 0))
    buffer.render(buf)
  end)
end)

utils.register_action("set_page_size", "Choose how many rows a page holds", function(buf)
  vim.ui.input({ prompt = "Rows per page: ", default = tostring(buf.state.limit) }, function(answer)
    local size = tonumber(answer)
    if not size then
      return
    end
    state.set_page_size(buf.state, math.floor(size))
    buffer.render(buf)
  end)
end)
