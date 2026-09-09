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
---@param value string
---@return string
local function without_hidden(value)
  local entries = {}
  for _, entry in ipairs(vim.split(value, ",", { plain = true })) do
    if entry ~= HIDDEN then
      entries[#entries + 1] = entry
    end
  end
  return table.concat(entries, ",")
end

--- Hide the real cursor if `bufnr` holds a table and show it if it does not.
---@param bufnr integer
function M.update(bufnr)
  local base = without_hidden(vim.o.guicursor)
  local setting = base
  if vim.bo[bufnr].filetype == "csv-table" then
    setting = base == "" and HIDDEN or base .. "," .. HIDDEN
  end
  if setting ~= vim.o.guicursor then
    vim.o.guicursor = setting
  end
end

--- Follow the cursor's visibility for the rest of the session.
---
--- Entering a buffer is what decides it, so a missed event lasts until the next
--- entry. `BufLeave` goes missing whenever a buffer is wiped while it is current
--- or a window opens with `noautocmd`, which telescope and snacks both do.
---@param group integer
function M.setup(group)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      M.update(event.buf)
    end,
  })
end

return M
