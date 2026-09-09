--[[
Registers the actions that move between pages.

The query knows how many rows its filters leave, so these turn a page without going
to xan first. A render that lands past the end steps back on its own, which covers
the moment before the first count arrives.
]]

local utils = require("csv-table.actions.utils")

utils.register_action("next_page", "Show the next page", function(view)
  if view.buffer.query.page_number >= view.buffer.query:last_page() then
    return vim.notify("csv-table: last page", vim.log.levels.INFO)
  end
  view.buffer.query:turn_page(1)
  view.buffer:render()
end)

utils.register_action("prev_page", "Show the previous page", function(view)
  view.buffer.query:turn_page(-1)
  view.buffer:render()
end)

utils.register_action("first_page", "Show the first page", function(view)
  view.buffer.query:goto_page(0)
  view.buffer:render()
end)

utils.register_action("last_page", "Show the last page", function(view)
  view.buffer.query:goto_page(view.buffer.query:last_page())
  view.buffer:render()
end)

utils.register_action("set_page_size", "Choose how many rows a page holds", function(view)
  local query = view.buffer.query
  vim.ui.input({ prompt = "Rows per page: ", default = tostring(query.limit) }, function(answer)
    local size = tonumber(answer)
    if not size then
      return
    end
    query:set_page_size(math.floor(size))
    view.buffer:render()
  end)
end)
