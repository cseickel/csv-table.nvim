--[[
How a searchable list is put in front of the user.

`vim.ui.select` is the one interface telescope, snacks, fzf-lua and nvim's own
prompt all implement, so a picker here runs in whichever of them the user has
installed and the plugin depends on none of them.

Enter is the only key `vim.ui.select` offers, so an entry has exactly one action.
]]

local M = {}

--- Offer `items` and run `on_choice` for the one picked. Choosing nothing is
--- how a picker is closed, and means the user wants nothing to happen.
---@generic T
---@param items T[]
---@param opts { prompt: string, format_item: fun(item: T): string }
---@param on_choice fun(item: T)
function M.choose(items, opts, on_choice)
  vim.ui.select(items, opts, function(item)
    if item then
      on_choice(item)
    end
  end)
end

return M
