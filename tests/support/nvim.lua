--[[
Enough of nvim's API for the pure modules to load under plain lua.

Splitting a string is what those modules ask `vim` for, so that is what this
holds. A module that reaches further belongs in a headless nvim run.
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
