--[[
How every failure reaches the user.
]]

local M = {}

---@param message string
function M.error(message)
  vim.notify("csv-table: " .. message, vim.log.levels.ERROR)
end

return M
