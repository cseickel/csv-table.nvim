--[[
Loads every module beside it and hands out the actions they registered, so adding
a module is enough to add its actions.

Registers the two actions that belong to no one topic:
- `refresh` reads the file again
- `clear_all` drops the filters, sort, marks and hidden columns
]]

local utils = require("csv-table.actions.utils")

utils.register_action("refresh", "Read the file again", function(view)
  view.buffer:render()
end)

utils.register_action("clear_all", "Clear filters, sort, marks and hidden columns", function(view)
  view.buffer.query:reset()
  view.buffer:render()
end)

-- Requiring a module is what registers its actions, so the require stands alone.
-- The directory comes from this file's own path, which keeps the list to the copy
-- of the plugin that is running.
local directory = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

for name in vim.fs.dir(directory) do
  local module = name:match("^(.+)%.lua$")
  if module and module ~= "init" then
    require("csv-table.actions." .. module)
  end
end

return {
  get_action = utils.get_action,
  get_all_actions = utils.get_all_actions,
}
