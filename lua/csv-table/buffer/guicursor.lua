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

--- `guicursor` with this plugin's entry taken out, which is the value it held
--- before a table hid the cursor. nvim rejects an empty entry.
---@param setting "normal"|"hidden"
---@return string
local function set_guicursors(setting)
  local value = vim.o.guicursor
  local entries = {}
  for _, entry in ipairs(vim.split(value, ",", { plain = true })) do
    if entry ~= HIDDEN then
      entries[#entries + 1] = entry
    end
  end
  if setting == "hidden" then
    table.insert(entries, HIDDEN)
  end
  local desired = #entries > 0 and table.concat(entries, ",") or ""
  if vim.o.guicursor ~= desired then
    print("setting guicursor to " .. setting)
    vim.o.guicursor = desired
  end
end

--- Hide the real cursor if `bufnr` holds a table and show it if it does not.
---@param buffer csv.Buffer | nil
function M.update_guicursor(buffer)
  local desired = buffer and "hidden" or "normal"
  set_guicursors(desired)
end

return M
