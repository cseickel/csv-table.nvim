--[[
Defines `csv.Buffer`, one per buffer nvim named after a spreadsheet: the query the
user is building, the page it drew, and one `csv.View` per window showing it.

A buffer is recorded the moment the read command fires, holding an empty file, an
empty query and an empty page, so a second read command finds it rather than
starting a second reader. The file, the query and the page are replaced as each one
is read.

The buffer stays nomodifiable. Its text is xan's output, and writing it back over
the file would destroy the file.
]]

local color = require("csv-table.buffer.color")
local file = require("csv-table.file")
local guicursor = require("csv-table.buffer.guicursor")
local page = require("csv-table.page")
local query = require("csv-table.query")
local reader = require("csv-table.reader")
local report = require("csv-table.utils.report")
local statuscolumn = require("csv-table.buffer.statuscolumn")
local view = require("csv-table.view")

local M = {}

---@class csv.Buffer
---@field bufnr integer
---@field query csv.Query The file, the reader and everything asked of them.
---@field page csv.Page   What is drawn now.
---@field read_state csv.QueryState What the drawn page was read for.
---@field views csv.View[] One per window that has shown this table.
local Buffer = {}
Buffer.__index = Buffer

-- nvim names a buffer with a number, so every entry point starts from one and this
-- is what turns it into the table that buffer holds.
---@type table<integer, csv.Buffer>
local buffers = {}

-- The autocommands a table buffer owns. Kept out of the group `setup` clears,
-- because these belong to one buffer: nvim drops them with the buffer, and a
-- second `setup` would take them from the tables already open.
local buffer_group = vim.api.nvim_create_augroup("csv-table-buffer", { clear = false })

---@param bufnr integer|nil
---@return csv.Buffer|nil
function M.get(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return buffers[bufnr]
end

---@param winnr integer
---@return csv.Buffer|nil
function M.for_window(winnr)
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  return M.get(bufnr)
end

--- Follow the cursor's visibility for the rest of the session.
---
--- Entering a buffer is what decides it, so a missed event lasts until the next
--- entry. `BufLeave` goes missing whenever a buffer is wiped while it is current
--- or a window opens with `noautocmd`, which telescope and snacks both do.
---@param group integer
function M.setup(group)
  -- used to check again after a delay, catches the case where events are
  -- missed. This is needed when db0query opens the window awithout
  -- focusing it.
  local function check_again()
    vim.defer_fn(function()
      local buffer = M.for_window(0)
      guicursor.update_guicursor(buffer)
    end, 100)
  end

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function(event)
      local buffer = M.for_window(0)
      guicursor.update_guicursor(buffer)
      check_again()
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      local buffer = M.for_window(0)
      guicursor.update_guicursor(buffer)
      check_again()
    end,
  })
end

---@param bufnr integer
---@param lines string[]
local function replace_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

--- The view a window with none of its own copies, which is the one in the window
--- just left, since that is the window a split came from.
---@param buffer csv.Buffer
---@return csv.View|nil
local function source_view(buffer)
  local previous = vim.fn.win_getid(vim.fn.winnr("#"))
  for _, held in ipairs(buffer.views) do
    if held.window == previous then
      return held
    end
  end
  return buffer.views[1]
end

--- The view `window` has of this table. A window with none of its own takes over a
--- closed window's view first, then one belonging to a window that has moved on to
--- another buffer, and copies a view only when neither is there, so a split starts
--- where the window it came from left off.
---@param window integer 0 for the current window, as the API takes it.
---@return csv.View
function Buffer:view(window)
  if window == 0 then
    window = vim.api.nvim_get_current_win()
  end

  for _, view in ipairs(self.views) do
    if view.window == window then
      return view
    end
  end

  for _, view in ipairs(self.views) do
    if not vim.api.nvim_win_is_valid(view.window) then
      view.window = window
      return view
    end
  end

  for _, view in ipairs(self.views) do
    if not view:on_screen() then
      view.window = window
      return view
    end
  end

  local source = source_view(self)
  local made = source and source:clone(window) or view.new(self, window)
  table.insert(self.views, made)
  return made
end
--
-- Entering one of nvim's visual modes is what says the user is picking cells out,
-- whichever key they entered it with. The pattern is the mode nvim came from and
-- the mode it went to, so `\22` is blockwise visual and a switch between two visual
-- modes matches as well.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = buffer_group,
  pattern = "*:[vV\22]",
  callback = function(event)
    local buffer = buffers[vim.api.nvim_get_current_buf()]
    if not buffer then
      return
    end

    local was = event.match:match("^(.*):")
    if was == "v" or was == "V" or was == "\22" then
      return buffer:view(0):change_kind()
    end
    buffer:view(0):start_extending()
  end,
})

-- Leaving a visual mode, where nvim writes `'<` and `'>` from the two ends it was
-- holding. The block the user picked out goes back over them, so `gv` brings the
-- cells back rather than nvim's own rectangle.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = buffer_group,
  pattern = "[vV\22]:*",
  callback = function()
    local buffer = M.get()
    if buffer then
      buffer:view(0):mark_selection()
    end
  end,
})

-- One namespace on the buffer draws the active cell and the selection, so the
-- window entered takes them from the window left.
vim.api.nvim_create_autocmd("WinEnter", {
  group = buffer_group,
  callback = function()
    local buffer = buffers[vim.api.nvim_get_current_buf()]
    if buffer then
      buffer:view(0):restore()
    end
  end,
})

-- `WinScrolled` names the windows that scrolled in `v:event`, keyed by window, and
-- the mouse wheel scrolls a window without entering it, so the current window is
-- not the one to record. The `all` key it also holds is not a window.
vim.api.nvim_create_autocmd("WinScrolled", {
  group = buffer_group,
  callback = function()
    for name in pairs(vim.v.event) do
      local window = tonumber(name)
      if window and vim.api.nvim_win_is_valid(window) then
        local buffer = buffers[vim.api.nvim_win_get_buf(window)]
        if buffer then
          buffer:view(window):remember()
        end
      end
    end
  end,
})

--- Run the query and draw the page it returns.
---@param on_rendered fun()|nil Runs once the new text is in the buffer.
function Buffer:render(on_rendered)
  self.query.reader:page(self.query, function(drawn)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    -- A page past the first that came back empty is a page past the end, which
    -- happens when the rows divide evenly into pages. Step back and draw the page
    -- that does have rows, so the user sees the view stay where it was.
    if drawn:row_count() < 1 and self.query.page_number > 0 then
      self.query:turn_page(-1)
      return self:render(on_rendered)
    end

    self.page = drawn
    local moved
    self.read_state, moved = self.query:after_read(self.read_state, drawn)
    replace_lines(self.bufnr, drawn.lines)
    color.redraw(self)
    -- Nothing here reads this. A winbar can pin the header line while the buffer is
    -- scrolled past it, and this is where it finds which line that is.
    vim.b[self.bufnr].table_header = drawn.header_line

    -- Every view, since a page that moved leaves the ends of a selection naming
    -- rows nobody picked, and a window that stepped away comes back to this view.
    if moved then
      for _, held in ipairs(self.views) do
        held:clear_selection()
      end
    end

    for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
      local shown = self:view(window)
      shown:restore()
      shown:draw()
    end

    if on_rendered then
      on_rendered()
    end
  end)
end

--- How wide `column` is drawn, in characters, or nil when it is hidden or nothing
--- has been drawn yet.
---@param column csv.Column
---@return integer|nil
function Buffer:column_width(column)
  local column_number = self.page:column_number(column)
  return column_number and self.page:cell_width(column_number) or nil
end

--- The rows of the result on display, counting from one.
---@return integer first
---@return integer last
function Buffer:row_range()
  local first = self.query:first_row_number()
  return first, first + self.page:row_count() - 1
end

--- Read the file and draw it. Every query the user built names columns of the file
--- being left, so a fresh read gets a fresh query. The views stay: a row id is a
--- position in the file, and a file read again holds the same rows in the same
--- places.
---@param sheet integer|nil 0-based.
---@param on_ready fun(buffer: csv.Buffer)|nil
function Buffer:load(sheet, on_ready)
  local buffer_reader = self.query.reader
  local path = self.query.file.path

  file.open(buffer_reader, path, sheet, function(opened)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    self.query = query.new(opened, buffer_reader, function()
      vim.cmd.redrawstatus()
    end)
    self.read_state = self.query:state(page.empty())
    self:render()
    if on_ready then
      on_ready(self)
    end
  end)
end

--- Read another sheet of the same workbook. Another sheet is other data, so every
--- row and column a view names is gone and the views go with them.
---@param sheet integer 0-based.
function Buffer:open_sheet(sheet)
  self.views = {}
  self:load(sheet)
end

--- A table is read by scrolling sideways, so wrapping would break every row into a
--- variable number of screen lines and unalign the columns. The gutter draws the row
--- number through `csv-table.buffer.statuscolumn`, which takes the place of the line
--- numbers.
---
--- Each is set through `vim.wo[window][0]`, which is `:setlocal`: the value holds
--- for this buffer in that window alone. `vim.wo[window]` is `:set`, which also
--- writes the value the window keeps for every buffer, and the next buffer shown in
--- the window would inherit it.
---@param bufnr integer
local function set_window_options(bufnr)
  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[window][0].wrap = false
    vim.wo[window][0].number = false
    vim.wo[window][0].relativenumber = false
    vim.wo[window][0].signcolumn = "no"
    vim.wo[window][0].statuscolumn = statuscolumn.EXPRESSION
  end
end

--- Record the buffer and take over its options and autocommands. The file has not
--- been read, so the query is over an empty file and the page is empty.
---@param bufnr integer
---@param path string
---@return csv.Buffer
local function record(bufnr, path)
  vim.bo[bufnr].buftype = "nowrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local empty = page.empty()
  local buffer = setmetatable({
    bufnr = bufnr,
    query = query.new(file.empty(path), reader.new(), function()
      vim.cmd.redrawstatus()
    end),
    page = empty,
    views = {},
  }, Buffer)
  buffer.read_state = buffer.query:state(empty)
  buffers[bufnr] = buffer

  set_window_options(bufnr)

  -- Shown in a window again, which `:buffer` reaches without firing the read
  -- command or `WinEnter`.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      set_window_options(bufnr)
      buffer:view(0):restore()
    end,
  })

  -- A motion this plugin leaves to nvim ends here, where the cell the user was
  -- aiming for becomes the active cell.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      if not buffers[bufnr] then
        return
      end
      local shown = buffer:view(0)
      shown:follow_cursor()
      shown:remember()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      buffer.query.reader:cancel()
      buffers[bufnr] = nil
    end,
  })

  return buffer
end

--- Take over `bufnr`, which nvim has named after a spreadsheet and left to this
--- plugin to read.
---@param bufnr integer
---@param on_ready fun(buffer: csv.Buffer)|nil
function M.attach(bufnr, on_ready)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return report.error("buffer has no file name")
  end

  -- `:edit` fires the read command again on a buffer already showing a table, and
  -- means refresh. This command owns the whole read, so setting the filetype is what
  -- tells whatever the user hangs off `FileType`.
  vim.bo[bufnr].filetype = "csv-table"

  local buffer = buffers[bufnr]
  if buffer then
    -- nvim empties the buffer before this runs, so the text has to go back whatever
    -- happens. When the file is the one the page was read from, the lines already in
    -- hand are that text, and xan has nothing to add.
    local drawn = buffer.page
    if #drawn.lines > 0 and buffer.query.file:version() == drawn.file_version then
      replace_lines(bufnr, drawn.lines)
      color.redraw(buffer)

      -- Every view names rows of this page, which is the one still in hand, so each
      -- window comes back to the cell it was left on.
      for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
        buffer:view(window):restore_viewport()
      end
      return
    end
  else
    buffer = record(bufnr, path)
  end

  buffer:load(buffer.query.file.sheet, on_ready)
end

return M
