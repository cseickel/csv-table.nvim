local buffer = require("csv-table.buffer")
local query = require("csv-table.query")
local state = require("csv-table.state")
local utils = require("csv-table.utils.utils.actions.utils")

local M = {}

---@type table<string, csv.Action>
M.utils.actions = {
  next_page = utils.action("Show the next page", function(buf)
    if buffer.at_last_page(buf) then
      return vim.notify("csv-table: last page", vim.log.levels.INFO)
    end
    state.turn_page(buf.state, 1)
    buffer.render(buf)
  end),

  prev_page = utils.action("Show the previous page", function(buf)
    state.turn_page(buf.state, -1)
    buffer.render(buf)
  end),

  first_page = utils.action("Show the first page", function(buf)
    state.goto_page(buf.state, 0)
    buffer.render(buf)
  end),

  last_page = utils.action("Show the last page", function(buf)
    query.count(buf.state, query.report, function(count)
      state.goto_page(buf.state, math.ceil(count / buf.state.limit) - 1)
      buffer.render(buf)
    end)
  end),

  set_page_size = utils.action("Choose how many rows a page holds", function(buf)
    vim.ui.input({ prompt = "Rows per page: ", default = tostring(buf.state.limit) }, function(answer)
      local size = tonumber(answer)
      if not size then
        return
      end
      state.set_page_size(buf.state, math.floor(size))
      buffer.render(buf)
    end)
  end),
}

return M
