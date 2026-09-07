--[[
Every action a key can run.

An action module registers what it defines as it loads, so this file loads the
modules beside it and then hands out what they registered. Adding a module is
enough to add its actions.

`refresh` and `clear_all` are here because they belong to no one topic.
]]

local buffer = require("csv-table.buffer")
local utils = require("csv-table.actions.utils")
local state = require("csv-table.state")

utils.register_action("refresh", "Read the file again", function(buf)
  buffer.render(buf)
end)

utils.register_action("clear_all", "Clear filters, sort, marks and hidden columns", function(buf)
  state.reset(buf.state)
  buffer.render(buf)
end)

-- Requiring a module is what registers its actions, so the require stands alone.
-- The directory comes from this file's own path, which keeps the list to the
-- copy of the plugin that is running.
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
