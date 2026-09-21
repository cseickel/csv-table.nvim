--[[
Defines `csv.Buffer`, one per buffer this plugin reads as a table: the query the
user is building, the page it drew, and one `csv.View` per window showing it.

A buffer is recorded the moment the read command fires, with an empty file, an
empty query and an empty page, so a second read command finds it instead of
starting a second reader. Each of the three is replaced as it is read.

The buffer stays nomodifiable. Its text is xan's output, and writing that back
over the file would destroy the file.
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

---@param window integer
---@return csv.Buffer|nil
function M.for_window(window)
  local bufnr = vim.api.nvim_win_get_buf(window)
  return M.get(bufnr)
end

--- Register every table buffer's autocommands again after a cleared group dropped
--- them.
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

--- The view in the window just left, which is the window a split came from, or
--- the first view when that window has none.
---@param buffer csv.Buffer
---@return csv.View|nil
local function source_view(buffer)
  local previous_window = vim.fn.win_getid(vim.fn.winnr("#"))
  for _, candidate in ipairs(buffer.views) do
    if candidate.window == previous_window then
      return candidate
    end
  end
  return buffer.views[1]
end

--- The view `window` has of this table. A window with none of its own takes over
--- a closed window's view first, then one whose window moved on to another buffer,
--- and copies the view of the window it was split from only when neither exists.
---@param window integer 0 for the current window, as the API takes it.
---@return csv.View
function Buffer:view(window)
  if window == 0 then
    window = vim.api.nvim_get_current_win()
  end

  for _, candidate in ipairs(self.views) do
    if candidate.window == window then
      return candidate
    end
  end

  for _, candidate in ipairs(self.views) do
    if not vim.api.nvim_win_is_valid(candidate.window) then
      candidate.window = window
      return candidate
    end
  end

  for _, candidate in ipairs(self.views) do
    if not candidate:on_screen() then
      candidate.window = window
      return candidate
    end
  end

  local source = source_view(self)
  local new_view = source and source:clone(window) or view.new(self, window)
  table.insert(self.views, new_view)
  return new_view
end

--- Run the query and draw the page it returns.
---@param on_rendered fun()|nil Runs once the new text is in the buffer.
function Buffer:render(on_rendered)
  self.query.reader:page(self.query, function(new_page)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    -- A page past the first that comes back empty is a page past the end, which
    -- happens when the rows divide evenly into pages.
    if new_page:row_count() < 1 and self.query.page_number > 0 then
      self.query:turn_page(-1)
      return self:render(on_rendered)
    end

    self.page = new_page
    local page_moved
    self.read_state, page_moved = self.query:after_read(self.read_state, new_page)
    replace_lines(self.bufnr, new_page.lines)
    color.redraw(self)
    -- For a winbar that pins the header line while the buffer is scrolled past it.
    vim.b[self.bufnr].table_header = new_page.header_line

    -- A page that moved leaves every selection naming rows nobody picked. Every
    -- view, including the ones whose windows are off screen.
    if page_moved then
      for _, window_view in ipairs(self.views) do
        window_view:clear_selection()
      end
    end

    for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
      local window_view = self:view(window)
      window_view:restore()
      window_view:draw()
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

--- Read the file and draw it. The query names columns of the file being left, so
--- a fresh read gets a fresh query. The views stay, because a row id is a position
--- in the file and a file read again holds the same rows in the same places.
---@param sheet integer|nil 0-based.
---@param on_ready fun(buffer: csv.Buffer)|nil
function Buffer:load(sheet, on_ready)
  local buffer_reader = self.query.reader
  local path = self.query.file.path

  file.open(buffer_reader, path, sheet, function(opened_file)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    self.query = query.new(opened_file, buffer_reader, function()
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
--- row and column a view names is gone, and the views go with them.
---@param sheet integer 0-based.
function Buffer:open_sheet(sheet)
  self.views = {}
  self:load(sheet)
end

--- A table is read by scrolling sideways. Wrapping would break each row into its
--- own number of screen lines and unalign the columns. The gutter shows the row
--- number from `csv-table.buffer.statuscolumn` in place of the line number.
local WINDOW_OPTIONS = {
  wrap = false,
  number = false,
  relativenumber = false,
  signcolumn = "no",
  statuscolumn = statuscolumn.EXPRESSION,
}

--- Every window option to put back, in the order they go back in.
---
--- `sidescrolloff` is here and not in `WINDOW_OPTIONS` because `csv-table.view.cursor`
--- sets it on every move, by which column the cursor is in. `relativenumber` goes
--- back before `number`, because nvim puts `number` back to a value it remembers
--- when `relativenumber` goes off, and that would undo a `number` already restored.
local RESTORED_WINDOW_OPTIONS = {
  "sidescrolloff",
  "wrap",
  "signcolumn",
  "statuscolumn",
  "relativenumber",
  "number",
}

--- The three `record` sets and `undress` puts back. Every other buffer option this
--- plugin touches is reset by nvim itself once the file is read as text again.
local BUFFER_OPTIONS = { "buftype", "swapfile", "modifiable" }

--- Put `saved_options` back on `window`. `vim.wo[window][0]` is the window's value
--- for the buffer it shows now, so the window has to be showing the table still.
---@param window integer
---@param saved_options table<string, any>
local function restore_window(window, saved_options)
  if not vim.api.nvim_win_is_valid(window) then
    return
  end
  for _, name in ipairs(RESTORED_WINDOW_OPTIONS) do
    vim.wo[window][0][name] = saved_options[name]
  end
end

--- Set `WINDOW_OPTIONS` on every window showing this table, saving what each had
--- first. A window that comes back to the table keeps the values saved the first
--- time, since the ones on it now are this plugin's.
function Buffer:dress_windows()
  for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
    if not self.window_options[window] then
      local saved_options = {}
      for _, name in ipairs(RESTORED_WINDOW_OPTIONS) do
        saved_options[name] = vim.wo[window][0][name]
      end
      self.window_options[window] = saved_options
    end

    for name, value in pairs(WINDOW_OPTIONS) do
      vim.wo[window][0][name] = value
    end
  end
end

--- Put every saved option back on this buffer and on the windows still showing it.
--- A window that moved to another buffer is left alone, since the saved value was
--- its value for this buffer and would land on the other one.
function Buffer:undress()
  for _, window in ipairs(vim.fn.win_findbuf(self.bufnr)) do
    local saved_options = self.window_options[window]
    if saved_options then
      restore_window(window, saved_options)
    end
  end
  self.window_options = {}

  for name, value in pairs(self.buffer_options) do
    vim.bo[self.bufnr][name] = value
  end
end

--- Register the autocommands this buffer owns, unless they are registered already.
---@param bufnr integer
function M.rebind(bufnr)
  local group = autocmds.group()

  -- `:bdelete` drops the buffer from `buffers` and leaves these registered, so a
  -- buffer opened again would get a second set. The three are registered together,
  -- so any one of them answers for all.
  local already_bound =
    vim.api.nvim_get_autocmds({ event = "CursorMoved", buffer = bufnr, group = group })
  if #already_bound > 0 then
    return
  end

  -- Shown in a window again. `:buffer` gets here without firing the read command
  -- or `WinEnter`.
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

  -- A motion left to nvim ends here, and the cell it reached becomes the active
  -- cell.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if not buffer then
        return
      end
      local current_view = buffer:view(0)
      current_view:follow_cursor()
      current_view:remember()
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

--- Record the buffer and take over its options and autocommands. The file is not
--- read yet, so the query is over an empty file and the page is empty.
---@param bufnr integer
---@param path string
---@return csv.Buffer
local function record(bufnr, path)
  local saved_options = {}
  for _, name in ipairs(BUFFER_OPTIONS) do
    saved_options[name] = vim.bo[bufnr][name]
  end

  vim.bo[bufnr].buftype = "nowrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local empty_page = page.empty()
  local buffer = setmetatable({
    bufnr = bufnr,
    query = query.new(file.empty(path), reader.new(), function()
      vim.cmd.redrawstatus()
    end),
    page = empty_page,
    views = {},
    buffer_options = saved_options,
    window_options = {},
  }, Buffer)
  buffer.read_state = buffer.query:state(empty_page)
  buffers[bufnr] = buffer

  buffer:dress_windows()
  M.rebind(bufnr)

  return buffer
end

--- Read the file into `bufnr` the way nvim would have.
---
--- Only `BufReadCmd` is ignored, so this plugin's read command stays out of the way
--- and every other read event still fires for filetype detection and for plugins on
--- `BufReadPost`. `undoreload = 0` keeps the drawn table out of the undo history,
--- where undoing back to it would leave the user holding xan's borders in a writable
--- buffer, one `:w` from the file.
---@param bufnr integer
---@return boolean whether the file is in the buffer.
local function read_as_text(bufnr)
  local saved_eventignore, saved_undoreload = vim.o.eventignore, vim.o.undoreload
  -- Appended rather than assigned, because another plugin may be part way through
  -- its own bookkeeping with `eventignore` set.
  vim.opt.eventignore:append("BufReadCmd")
  vim.o.undoreload = 0

  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd.edit()
  end)

  vim.o.eventignore, vim.o.undoreload = saved_eventignore, saved_undoreload
  if not ok then
    report.error(tostring(err))
  end
  return ok
end

--- Give `bufnr` back to nvim: every option, keymap, autocommand and extmark this
--- plugin set is undone, and the file is read in place of the table.
---@param bufnr integer
function M.detach(bufnr)
  local buffer = buffers[bufnr]
  if not buffer then
    return
  end

  buffer.query.reader:cancel()
  buffer:undress()
  -- Drawing the table left `modified` true. `undress` has just put a writable
  -- `buftype` back, so nvim now treats that as an unsaved change and would refuse
  -- the read below.
  vim.bo[bufnr].modified = false
  buffers[bufnr] = nil

  autocmds.release(bufnr)
  color.clear(bufnr)
  view.clear(bufnr)
  vim.b[bufnr].table_header = nil
  vim.bo[bufnr].filetype = ""

  if not read_as_text(bufnr) then
    -- The buffer still holds the drawn table, which must never be written to the
    -- file.
    vim.bo[bufnr].buftype = "nowrite"
    vim.bo[bufnr].modifiable = false
  end
  guicursor.update(M.for_window(0))
end

--- Take over `bufnr` from inside its read command, which has left the whole read to
--- this plugin.
---@param bufnr integer
---@param on_ready fun(buffer: csv.Buffer)|nil
function M.attach(bufnr, on_ready)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return report.error("buffer has no file name")
  end

  -- A read command owns the whole read, so nothing else sets the filetype.
  vim.bo[bufnr].filetype = "csv-table"

  local buffer = buffers[bufnr]
  if buffer then
    -- `:edit` on a buffer already showing a table means refresh. nvim empties the
    -- buffer before the read command runs, so the text has to go back whatever
    -- happens. When the file is unchanged since the page was read, the lines in hand
    -- are that text.
    local current_page = buffer.page
    if #current_page.lines > 0 and buffer.query.file:version() == current_page.file_version then
      replace_lines(bufnr, current_page.lines)
      color.redraw(buffer)

      -- Every view names rows of this page, so each window comes back to the cell
      -- it was left on.
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
