--[[
The augroup this plugin registers under, the autocommands that last the session,
and the read command that turns a file into a table, over the configured extensions
and over any one buffer `claim` takes.

`apply` creates the group fresh, so running `setup` again replaces every
autocommand with the ones this version of the plugin defines. That takes the
buffer-local ones with it, which is why `apply` ends by giving them back to the
tables already open.

- `apply` registers the session autocommands and the read command over the
  configured extensions
- `group` is the augroup, which is also where a buffer registers its own
- `covers` says whether the read command already takes a path
- `claim` reads one buffer as a table whatever its name
- `release` gives one buffer back to nvim

`csv-table.buffer` and `csv-table.actions` are reached inside the callbacks rather
than required at the top, because both lead back to `csv-table.buffer`, which
requires this module for `group`.
]]

local color = require("csv-table.buffer.color")
local guicursor = require("csv-table.buffer.guicursor")
local keymaps = require("csv-table.keymaps")
local mode = require("csv-table.utils.mode")

local M = {}

---@type integer
local augroup

-- The extensions the read command was registered over, lowercased.
---@type table<string, true>
local wanted = {}

-- Every buffer `claim` took. nvim drops a buffer-local autocommand when the buffer
-- is wiped and `apply` drops it when it takes the group, so this is what says a
-- buffer should have one, as against what says it has one now.
---@type table<integer, true>
local claimed = {}

local function buffer()
  return require("csv-table.buffer")
end

---@param buf csv.Buffer
local function apply_keymaps(buf)
  local actions = require("csv-table.actions")

  for _, binding in ipairs(keymaps.resolve()) do
    if binding.command then
      vim.keymap.set({ "n", "x" }, binding.key, binding.command, {
        buffer = buf.bufnr,
        desc = "csv-table: nvim's " .. binding.command,
      })
    else
      local action = actions.get_action(binding.action)
      if not action then
        error(
          string.format("csv-table: key %q names unknown action %q", binding.key, binding.action)
        )
      end

      vim.keymap.set({ "n", "x" }, binding.key, function()
        if not binding.stays_visual then
          mode.leave_visual()
        end
        action.run(buf:view(0))
      end, { buffer = buf.bufnr, desc = "csv-table: " .. action.description })
    end
  end

  -- A click lands exactly where it was pointed, and the view needs to know that,
  -- since any other move that ends up in the cell it started in was a motion too
  -- small to leave the cell. The expression hands the key back so nvim still does
  -- the click itself.
  vim.keymap.set({ "n", "x" }, "<LeftMouse>", function()
    buf:view(0):click()
    return "<LeftMouse>"
  end, { buffer = buf.bufnr, expr = true, desc = "csv-table: follow the click" })
end

--- Take this plugin's keys off `bufnr`. Every one `apply_keymaps` sets is given a
--- description starting `csv-table: `, which is what tells them from the user's own.
---@param bufnr integer
local function clear_keymaps(bufnr)
  for _, name in ipairs({ "n", "x" }) do
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, name)) do
      if mapping.desc and mapping.desc:find("^csv%-table: ") then
        vim.api.nvim_buf_del_keymap(bufnr, name, mapping.lhs)
      end
    end
  end
end

--- Follow the cursor's visibility into whichever window the user is in, since
--- `guicursor` is global and the current window is the one that decides it.
---
--- Telescope and snacks open a window with `noautocmd`, so neither event fires and
--- the cursor keeps what the window before it decided. The second read catches that
--- once the window has finished opening.
local function follow_current_window()
  guicursor.update_guicursor(buffer().for_window(0))
  vim.defer_fn(function()
    guicursor.update_guicursor(buffer().for_window(0))
  end, 100)
end

--- The augroup every autocommand of this plugin belongs to, the ones a buffer
--- registers for itself included.
---@return integer
function M.group()
  return augroup
end

--- Whether the read command `apply` registered already takes `path`. A claim on a
--- path it takes would be a second autocommand on the same read.
---
--- An extension holds periods of its own, so this asks what the pattern asks: does
--- the name end in a dot and the extension. A name that is only the extension does
--- not, since `*.test.ps1` has nothing for the `*` to match in `test.ps1`.
---@param path string
---@return boolean
function M.covers(path)
  local name = vim.fn.fnamemodify(path, ":t"):lower()
  for extension in pairs(wanted) do
    if name:sub(-#extension - 1) == "." .. extension then
      return true
    end
  end
  return false
end

--- Read `bufnr` as a table from here on, whatever its name says. The claim lasts
--- until the buffer is wiped: nvim drops the autocommand then, and `apply` gives it
--- back after anything else takes it.
---@param bufnr integer
function M.claim(bufnr)
  claimed[bufnr] = true

  -- nvim runs every autocommand matching a read, so a second one of ours here would
  -- read the file twice. Another plugin's is its own business.
  local held = vim.api.nvim_get_autocmds({
    event = "BufReadCmd",
    buffer = bufnr,
    group = augroup,
  })
  if #held > 0 then
    return
  end

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = augroup,
    buffer = bufnr,
    callback = function(event)
      buffer().attach(event.buf, apply_keymaps)
    end,
  })
end

--- Drop everything this buffer holds from this plugin, the claim included, so nvim
--- reads it as a plain file from here on. `apply` will not give any of it back.
---@param bufnr integer
function M.release(bufnr)
  claimed[bufnr] = nil
  vim.api.nvim_clear_autocmds({ buffer = bufnr, group = augroup })
  clear_keymaps(bufnr)
end

--- The autocommand pattern for a name ending in `extension`, in any case. nvim
--- matches a pattern case sensitively unless `fileignorecase` is on, and an
--- extension names the same format however it is written.
---@param extension string
---@return string
local function any_case(extension)
  return "*."
    .. (extension:gsub("%a", function(letter)
      return "[" .. letter:lower() .. letter:upper() .. "]"
    end))
end

--- Register every autocommand, replacing whatever a previous `setup` left.
---@param extensions string[] The file extensions that open as a table.
function M.apply(extensions)
  augroup = vim.api.nvim_create_augroup("csv-table", { clear = true })

  wanted = {}
  local patterns = {}
  for index, extension in ipairs(extensions) do
    wanted[extension:lower()] = true
    patterns[index] = any_case(extension)
  end

  -- A colorscheme runs `highlight clear` first, which takes every group this plugin
  -- defines with it.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = color.define_groups,
  })

  -- A `BufReadCmd` replaces nvim's own read, so a file this matches never reaches
  -- the buffer as text.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = augroup,
    pattern = patterns,
    callback = function(event)
      buffer().attach(event.buf, apply_keymaps)
    end,
  })

  -- Either event arrives without the other: `:buffer` changes the buffer under one
  -- window, and `<C-w>w` changes the window over one buffer.
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = augroup,
    callback = follow_current_window,
  })

  -- Entering one of nvim's visual modes is what says the user is picking cells out,
  -- whichever key they entered it with. The pattern is the mode nvim came from and
  -- the mode it went to, so `\22` is blockwise visual and a switch between two
  -- visual modes matches as well.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    pattern = "*:[vV\22]",
    callback = function(event)
      local buf = buffer().get()
      if not buf then
        return
      end

      local was = event.match:match("^(.*):")
      if mode.is_visual(was) then
        return buf:view(0):change_kind()
      end
      buf:view(0):start_extending()
    end,
  })

  -- Leaving a visual mode, where nvim writes `'<` and `'>` from the two ends it was
  -- holding. The block the user picked out goes back over them, so `gv` brings the
  -- cells back rather than nvim's own rectangle.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    pattern = "[vV\22]:*",
    callback = function()
      local buf = buffer().get()
      if buf then
        buf:view(0):mark_selection()
      end
    end,
  })

  -- One namespace on the buffer draws the active cell and the selection, so the
  -- window entered takes them from the window left.
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      local buf = buffer().get()
      if buf then
        buf:view(0):restore()
      end
    end,
  })

  -- `WinScrolled` names the windows that scrolled in `v:event`, keyed by window, and
  -- the mouse wheel scrolls a window without entering it, so the current window is
  -- not the one to record. The `all` key it also holds is not a window.
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    callback = function()
      for name in pairs(vim.v.event) do
        local window = tonumber(name)
        if window and vim.api.nvim_win_is_valid(window) then
          local buf = buffer().for_window(window)
          if buf then
            buf:view(window):remember()
          end
        end
      end
    end,
  })

  -- Creating the group cleared what every open table had registered for itself,
  -- claims included, so each one gets it back. A claim on a wiped buffer is the only
  -- one with nothing to go back to.
  buffer().rebind_all()
  for bufnr in pairs(claimed) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.claim(bufnr)
    else
      claimed[bufnr] = nil
    end
  end
end

return M
