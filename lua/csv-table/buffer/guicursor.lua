--[[
Hides the real cursor while a table is on screen, since the active cell is drawn
in its place.

`guicursor` is global and holds one entry per mode, the last entry for a mode
winning, so hiding is appending an entry and showing is taking it back out.
Rebuilding from the value leaves another plugin's cursor styling as that plugin
set it.
]]

local M = {}

-- The modes a table buffer is read in. The command line keeps its cursor, so `:`,
-- `/` and every `vim.ui.input` prompt can be typed into.
local HIDDEN = "n-v-o:CsvHiddenCursor"

--- Rebuild `guicursor` with this plugin's entry either in or out, leaving every
--- other entry as the plugin that wrote it left it.
---@param setting "normal"|"hidden"
local function set_guicursor(setting)
  local entries = {}
  for _, entry in ipairs(vim.split(vim.o.guicursor, ",", { plain = true })) do
    if entry ~= HIDDEN then
      entries[#entries + 1] = entry
    end
  end
  if setting == "hidden" then
    table.insert(entries, HIDDEN)
  end

  local desired = table.concat(entries, ",")
  if vim.o.guicursor ~= desired then
    vim.o.guicursor = desired
  end
end

--- Hide the real cursor while the user is in a table, and show it again anywhere
--- else.
---@param buffer csv.Buffer|nil The table the current window holds, if it holds one.
function M.update_guicursor(buffer)
  set_guicursor(buffer and "hidden" or "normal")
end

return M
