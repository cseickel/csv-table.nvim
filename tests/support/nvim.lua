--[[
Enough of nvim's API for the pure modules to load under plain lua.

The modules under test reach for `vim` only to split strings, so this covers
that and stops at the first thing they actually use. A module that needs more
than this belongs in a headless nvim run instead.
]]

_G.vim = {
  --- `vim.split` with `plain`, which is the only form the pure modules use.
  ---@param text string
  ---@param separator string
  ---@return string[]
  split = function(text, separator)
    local parts = {}
    local pattern = "([^" .. separator .. "]*)" .. separator .. "?"
    for piece in text:gmatch(pattern) do
      table.insert(parts, piece)
    end
    -- `gmatch` matches the empty string past the last separator.
    table.remove(parts)
    return parts
  end,
}
