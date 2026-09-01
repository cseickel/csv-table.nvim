--[[
The actions that move between pages.

Nothing counts the rows a filter matches until asked, so `last_page` is the only
one of these that goes to xan before it can move.
]]

local buffer = require("csv-table.buffer")
local query = require("csv-table.query")
local state = require("csv-table.state")
local utils = require("csv-table.actions.utils")

utils.register_action("next_page", "Show the next page", function(buf)
  if buffer.at_last_page(buf) then
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
  query.count(buf.state, query.report, function(count)
    state.goto_page(buf.state, math.ceil(count / buf.state.limit) - 1)
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
