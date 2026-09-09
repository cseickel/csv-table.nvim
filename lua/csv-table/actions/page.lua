--[[
Registers the actions that move between pages.

The query knows how many rows its filters leave, so these turn a page without
going to xan first. A render that lands past the end steps back on its own, which
covers the moment before the first count arrives.
]]

local buffer = require("csv-table.buffer")
local utils = require("csv-table.actions.utils")

utils.register_action("next_page", "Show the next page", function(buf)
  if buf.query.page_number >= buf.query:last_page() then
    return vim.notify("csv-table: last page", vim.log.levels.INFO)
  end
  buf.query:turn_page(1)
  buffer.render(buf)
end)

utils.register_action("prev_page", "Show the previous page", function(buf)
  buf.query:turn_page(-1)
  buffer.render(buf)
end)

utils.register_action("first_page", "Show the first page", function(buf)
  buf.query:goto_page(0)
  buffer.render(buf)
end)

utils.register_action("last_page", "Show the last page", function(buf)
  buf.query:goto_page(buf.query:last_page())
  buffer.render(buf)
end)

utils.register_action("set_page_size", "Choose how many rows a page holds", function(buf)
  vim.ui.input(
    { prompt = "Rows per page: ", default = tostring(buf.query.limit) },
    function(answer)
      local size = tonumber(answer)
      if not size then
        return
      end
      buf.query:set_page_size(math.floor(size))
      buffer.render(buf)
    end
  )
end)
