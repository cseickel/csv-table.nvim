--[[
Enough of nvim's API for the pure modules to load under plain lua.

Splitting a string and comparing two tables are what those modules ask `vim` for,
so that is what this holds. A module that reaches further belongs in a headless
nvim run.
]]

--- `vim.deep_equal`: two values are equal when every key of each holds an equal
--- value in the other.
---@param left any
---@param right any
---@return boolean
local function deep_equal(left, right)
  if left == right then
    return true
  end
  if type(left) ~= "table" or type(right) ~= "table" then
    return false
  end

  for key, value in pairs(left) do
    if not deep_equal(value, right[key]) then
      return false
    end
  end
  for key in pairs(right) do
    if left[key] == nil then
      return false
    end
  end
  return true
end

_G.vim = {
  deep_equal = deep_equal,
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
