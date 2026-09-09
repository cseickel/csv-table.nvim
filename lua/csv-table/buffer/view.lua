--[[
Remembers where each window is looking, so a buffer that is emptied and filled
again comes back the way the user left it.
]]

local cursor = require("csv-table.buffer.cursor")

local M = {}

---@type table<integer, table>
local views = {}

-- These autocommands belong to the plugin rather than to one buffer, so they are
-- registered once, on the group `csv-table.buffer` also uses.
local group = vim.api.nvim_create_augroup("csv-table-buffer", { clear = false })

--- Keep where the current window is looking.
function M.remember()
  views[vim.api.nvim_get_current_win()] = vim.fn.winsaveview()
end

-- `WinScrolled` reports a window rather than a buffer, so it is registered once
-- and asks whether the window it names is showing a table.
vim.api.nvim_create_autocmd("WinScrolled", {
  group = group,
  callback = function()
    if vim.bo.filetype == "csv-table" then
      M.remember()
    end
  end,
})

-- nvim reuses window handles, so a view left behind would describe the next
-- window to take the number.
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    views[tonumber(event.match)] = nil
  end,
})

--- Look at `window` the way it was left. The active cell goes back first, so nvim
--- has the cursor on the right line before the view is asked for, and the view
--- then decides which part of the table is on screen.
---
--- Scheduled, because `:edit` puts the cursor on line 1 once the read command it
--- fired has returned, and this has to land after that.
---@param buffer csv.Buffer
---@param window integer
function M.restore(buffer, window)
  local cell = cursor.active_cell(buffer, window)
  local view = views[window]

  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_buf(window) ~= buffer.bufnr then
      return
    end

    cursor.move_to(buffer, window, cell)
    if view then
      vim.api.nvim_win_call(window, function()
        vim.fn.winrestview(view)
      end)
    end
  end)
end

return M
