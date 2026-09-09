--[[
Measures and cuts text by characters rather than bytes, which is what a padded
table counts.
]]

local M = {}

--- How many characters a value holds. The `#` operator counts bytes, and a sort
--- arrow in a header is three of them.
---@param value string
---@return integer
function M.length(value)
  local _, count = value:gsub("[^\128-\191]", "")
  return count
end

--- The first `length` characters of a value, ending in an ellipsis when anything
--- was dropped.
---@param value string
---@param length integer
---@return string
function M.truncate(value, length)
  if M.length(value) <= length then
    return value
  end
  if length <= 1 then
    return "…"
  end

  local kept = {}
  for character in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #kept + 1 >= length then
      break
    end
    kept[#kept + 1] = character
  end
  return table.concat(kept) .. "…"
end

return M
