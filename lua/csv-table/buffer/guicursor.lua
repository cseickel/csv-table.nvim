--[[
Hides the real cursor while a table is on screen, since the active cell is drawn
in its place.

`guicursor` is global and holds one entry per mode, and the last entry for a mode
wins. Hiding the cursor appends an entry and showing it removes that entry.
Rebuilding the value around that entry leaves another plugin's cursor styling
alone.
]]

local M = {}

-- The modes a table is read in. The command line keeps its cursor, so `:`, `/`
-- and `vim.ui.input` can be typed into.
local HIDDEN_CURSOR_ENTRY = "n-v-o:CsvHiddenCursor"

--- Write `guicursor` with this plugin's entry in or out.
---@param setting "normal"|"hidden"
local function set_guicursor(setting)
  local entries = {}
  for _, entry in ipairs(vim.split(vim.o.guicursor, ",", { plain = true })) do
    if entry ~= HIDDEN_CURSOR_ENTRY then
      entries[#entries + 1] = entry
    end
  end
  if setting == "hidden" then
    table.insert(entries, HIDDEN_CURSOR_ENTRY)
  end

  local new_value = table.concat(entries, ",")
  if vim.o.guicursor ~= new_value then
    vim.o.guicursor = new_value
  end
end

--- Hide the cursor when the current window shows a table, and show it otherwise.
---@param buffer csv.Buffer|nil The table the current window holds, if it holds one.
function M.update(buffer)
  set_guicursor(buffer and "hidden" or "normal")
end

return M
