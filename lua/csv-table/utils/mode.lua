--[[
What nvim's mode says about picking cells out.

Charwise, linewise and blockwise count as one thing here, because a selection is
cells rather than the text they are painted in.
]]

local M = {}

-- nvim's three visual modes, where `\22` is CTRL-V.
local VISUAL = { v = true, V = true, ["\22"] = true }

local ESC = "\27"

---@param name string A mode, as `mode()` names it.
---@return boolean
function M.is_visual(name)
  return VISUAL[name] == true
end

---@return boolean
function M.in_visual()
  return M.is_visual(vim.fn.mode())
end

--- Feed `<Esc>` when nvim is in a visual mode.
---
--- The flags are `nx`. `n` keeps the key off the mappings, where `<Esc>` in a table
--- buffer runs `clear_selection`. `x` runs the typeahead now rather than leaving
--- `<Esc>` in it, so it never reaches a window the caller goes on to open. Whatever
--- else is in the typeahead runs now too, which for a macro holding `vly` is
--- everything after the `y`.
function M.leave_visual()
  if M.in_visual() then
    vim.api.nvim_feedkeys(ESC, "nx", false)
  end
end

return M
