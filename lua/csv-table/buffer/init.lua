--[[
Defines `csv.Buffer`, one per buffer this plugin reads as a table: the query the
user is building, the page it drew, and one `csv.View` per window showing it.

A buffer is recorded the moment the read command fires, holding an empty file, an
empty query and an empty page, so a second read command finds it rather than
starting a second reader. The file, the query and the page are replaced as each one
is read.

The buffer stays nomodifiable. Its text is xan's output, and writing it back over
the file would destroy the file.
]]

local autocmds = require("csv-table.autocmds")
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
---@field buffer_options table<string, any> What the buffer held before `record`.
---@field window_options table<integer, table<string, any>> What each window held, keyed by window.
local Buffer = {}
Buffer.__index = Buffer

-- nvim names a buffer with a number, so every entry point starts from one and this
-- is what turns it into the table that buffer holds.
---@type table<integer, csv.Buffer>
local buffers = {}

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

--- Register the autocommands of every buffer holding a table, which is what a
--- cleared group costs them.
function M.rebind_all()
  for bufnr in pairs(buffers) do
    M.rebind(bufnr)
  end
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
local WINDOW_OPTIONS = {
  wrap = false,
  number = false,
  relativenumber = false,
  signcolumn = "no",
  statuscolumn = statuscolumn.EXPRESSION,
}

--- Every window option a window has to get back, in the order they go back in.
---
--- `sidescrolloff` is here and not above because `csv-table.view.cursor` sizes it to
--- the column the cursor is parked in. `number` comes after `relativenumber`,
--- because nvim puts `number` back to a value it remembers when `relativenumber`
--- goes off, so a window with `number` on would lose it.
local RESTORED = {
  "sidescrolloff",
  "wrap",
  "signcolumn",
  "statuscolumn",
  "relativenumber",
  "number",
}

--- The options nvim resets on its own once the buffer is read as a file again are
--- not here. These three are ours to put back.
local BUFFER_OPTIONS = { "buftype", "swapfile", "modifiable" }

--- Put `held` back on `window`. `vim.wo[window][0]` is the window's value for the
--- buffer it shows, which is the one `dress_windows` read and wrote over, so the
--- window has to be showing that buffer still.
---@param window integer
---@param held table<string, any>
local function restore_window(window, held)
  if not vim.api.nvim_win_is_valid(window) then
    return
  end
  for _, name in ipairs(RESTORED) do
    vim.wo[window][0][name] = held[name]
  end
end

--- Dress every window showing this table, keeping what each window had so it can be
--- put back. A window that comes back to the table keeps the values it had the first
--- time, since the ones on it now are this plugin's.
function Buffer:dress_windows()
  for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
    if not self.window_options[window] then
      local held = {}
      for _, name in ipairs(RESTORED) do
        held[name] = vim.wo[window][0][name]
      end
      self.window_options[window] = held
    end

    for name, value in pairs(WINDOW_OPTIONS) do
      vim.wo[window][0][name] = value
    end
  end
end


--- Put every option back the way this buffer and the windows still on it had it. A
--- window that moved to another buffer is left alone, since the value read there
--- belongs to the pair it made with this one.
function Buffer:undress()
  for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
    local held = self.window_options[window]
    if held then
      restore_window(window, held)
    end
  end
  self.window_options = {}

  for name, value in pairs(self.buffer_options) do
    vim.bo[self.bufnr][name] = value
  end
end

--- Register the autocommands this buffer owns. `record` calls it when the buffer is
--- taken over, and `csv-table.autocmds` again once a reload has replaced the group
--- these belong to.
---@param bufnr integer
function M.rebind(bufnr)
  local group = autocmds.group()

  -- `:bdelete` drops the buffer from `buffers` and leaves these registered, so a
  -- buffer opened again would have two of each. The three are registered together,
  -- and any one of them says so.
  local held = vim.api.nvim_get_autocmds({ event = "CursorMoved", buffer = bufnr, group = group })
  if #held > 0 then
    return
  end

  -- Shown in a window again, which `:buffer` reaches without firing the read
  -- command or `WinEnter`.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if buffer then
        buffer:dress_windows()
        buffer:view(0):restore()
      end
    end,
  })

  -- A motion this plugin leaves to nvim ends here, where the cell the user was
  -- aiming for becomes the active cell.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if not buffer then
        return
      end
      local shown = buffer:view(0)
      shown:follow_cursor()
      shown:remember()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if buffer then
        buffer.query.reader:cancel()
      end
      buffers[bufnr] = nil
    end,
  })
end

--- Record the buffer and take over its options and autocommands. The file has not
--- been read, so the query is over an empty file and the page is empty.
---@param bufnr integer
---@param path string
---@return csv.Buffer
local function record(bufnr, path)
  local held = {}
  for _, name in ipairs(BUFFER_OPTIONS) do
    held[name] = vim.bo[bufnr][name]
  end

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
    buffer_options = held,
    window_options = {},
  }, Buffer)
  buffer.read_state = buffer.query:state(empty)
  buffers[bufnr] = buffer

  buffer:dress_windows()
  M.rebind(bufnr)

  return buffer
end

--- Read the file into `bufnr` the way nvim would have.
---
--- `BufReadCmd` is held off so this plugin's own read command leaves the buffer
--- alone, and every other read event still fires, which is what a plugin hanging
--- off `BufReadPost` and nvim's own filetype detection need. `undoreload` is zero so
--- the drawn table stays out of the undo history: undoing back to it would leave the
--- user holding xan's borders in a writable buffer, one `:w` from the file.
---@param bufnr integer
---@return boolean whether the file is in the buffer.
local function read_as_text(bufnr)
  local ignored, reload = vim.o.eventignore, vim.o.undoreload
  -- Appended rather than assigned, because another plugin may be part way through
  -- its own bookkeeping with `eventignore` set.
  vim.opt.eventignore:append("BufReadCmd")
  vim.o.undoreload = 0

  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd.edit()
  end)

  vim.o.eventignore, vim.o.undoreload = ignored, reload
  if not ok then
    report.error(tostring(err))
  end
  return ok
end

--- Give `bufnr` back to nvim: every option, keymap, autocommand and extmark this
--- plugin set undone, and the file read in place of the table.
---@param bufnr integer
function M.detach(bufnr)
  local buffer = buffers[bufnr]
  if not buffer then
    return
  end

  buffer.query.reader:cancel()
  buffer:undress()
  -- A writable `buftype` makes nvim compare the buffer against the file and call
  -- the drawn table an unsaved change, which would stop the read below.
  vim.bo[bufnr].modified = false
  buffers[bufnr] = nil

  autocmds.release(bufnr)
  color.clear(bufnr)
  view.clear(bufnr)
  vim.b[bufnr].table_header = nil
  vim.bo[bufnr].filetype = ""

  if not read_as_text(bufnr) then
    -- The buffer still holds the drawn table, so it goes back to being one nobody
    -- can write over the file.
    vim.bo[bufnr].buftype = "nowrite"
    vim.bo[bufnr].modifiable = false
  end
  guicursor.update_guicursor(M.for_window(0))
end

--- Take over `bufnr`, whose read command has left the whole read to this plugin.
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
