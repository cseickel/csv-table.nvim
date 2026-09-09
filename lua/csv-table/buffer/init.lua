--[[
Defines `csv.Buffer`, one per buffer nvim named after a spreadsheet: the query
the user is building and the page it drew.

A buffer is recorded the moment the read command fires, holding an empty file, an
empty query and an empty page, so a second read command finds it rather than
starting a second reader. The file, the query and the page are replaced as each
one is read.

The buffer stays nomodifiable. Its text is xan's output, and writing it back over
the file would destroy the file.
]]

local color = require("csv-table.buffer.color")
local cursor = require("csv-table.buffer.cursor")
local file = require("csv-table.file")
local guicursor = require("csv-table.buffer.guicursor")
local movement = require("csv-table.buffer.movement")
local page = require("csv-table.page")
local query = require("csv-table.query")
local reader = require("csv-table.reader")
local report = require("csv-table.utils.report")
local statuscolumn = require("csv-table.buffer.statuscolumn")
local view = require("csv-table.buffer.view")

local M = {}

---@class csv.Buffer
---@field bufnr integer
---@field query csv.Query The file, the reader and everything asked of them.
---@field page csv.Page   What is drawn now.
---@field read_state csv.QueryState What the drawn page was read for.

---@type table<integer, csv.Buffer>
local buffers = {}

-- The autocommands a table buffer owns. Kept out of the group `setup` clears,
-- because these belong to one buffer: nvim drops them with the buffer, and a
-- second `setup` would take them from the tables already open.
local buffer_group = vim.api.nvim_create_augroup("csv-table-buffer", { clear = false })

---@param bufnr integer
---@return csv.Buffer|nil
function M.get(bufnr)
  return buffers[bufnr]
end

---@param bufnr integer
---@param lines string[]
local function replace_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

-- Entering one of nvim's visual modes is what says the user is picking cells out,
-- whichever key they entered it with. The pattern is the mode nvim came from and
-- the mode it went to, so `\22` is blockwise visual and a switch between two
-- visual modes matches as well.
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
      return movement.change_kind(buffer)
    end
    movement.start_extending(buffer, 0)
  end,
})

-- Leaving a visual mode, where nvim writes `'<` and `'>` from the two ends it was
-- holding. The block the user picked out goes back over them, so `gv` brings the
-- cells back rather than nvim's own rectangle.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = buffer_group,
  pattern = "[vV\22]:*",
  callback = function()
    local buffer = buffers[vim.api.nvim_get_current_buf()]
    if buffer then
      movement.mark_selection(buffer)
    end
  end,
})

--- Run the query for `buffer` and draw the page it returns.
---@param buffer csv.Buffer
---@param on_rendered fun()|nil Runs once the new text is in the buffer.
function M.render(buffer, on_rendered)
  buffer.query.reader:page(buffer.query, function(drawn)
    if not vim.api.nvim_buf_is_valid(buffer.bufnr) then
      return
    end

    -- A page past the first that came back empty is a page past the end, which
    -- happens when the rows divide evenly into pages. Step back and draw the page
    -- that does have rows, so the user sees the view stay where it was.
    if drawn:row_count() < 1 and buffer.query.page_number > 0 then
      buffer.query:turn_page(-1)
      return M.render(buffer, on_rendered)
    end

    buffer.page = drawn
    buffer.read_state = buffer.query:after_read(buffer.read_state, drawn)
    replace_lines(buffer.bufnr, drawn.lines)
    color.redraw(buffer)
    -- Nothing here reads this. A winbar can pin the header line while the buffer
    -- is scrolled past it, and this is where it finds which line that is.
    vim.b[buffer.bufnr].table_header = drawn.header_line

    local window = vim.fn.bufwinid(buffer.bufnr)
    if window ~= -1 then
      cursor.restore(buffer, window)
    end

    if on_rendered then
      on_rendered()
    end
  end)
end

--- How wide `column` is drawn, in characters, or nil when it is hidden or nothing
--- has been drawn yet.
---@param buffer csv.Buffer
---@param column csv.Column
---@return integer|nil
function M.column_width(buffer, column)
  local column_number = buffer.page:column_number(column)
  return column_number and buffer.page:cell_width(column_number) or nil
end

--- The rows of the result on display, counting from one.
---@param buffer csv.Buffer
---@return integer first
---@return integer last
function M.row_range(buffer)
  local first = buffer.query:first_row_number()
  return first, first + buffer.page:row_count() - 1
end

--- Read the file and draw it. Every query the user built names columns of the
--- sheet being left, so a fresh file gets a fresh query.
---@param buffer csv.Buffer
---@param sheet integer|nil 0-based.
---@param on_ready fun(buffer: csv.Buffer)|nil
local function load(buffer, sheet, on_ready)
  local buffer_reader = buffer.query.reader
  local path = buffer.query.file.path

  file.open(buffer_reader, path, sheet, function(opened)
    if not vim.api.nvim_buf_is_valid(buffer.bufnr) then
      return
    end

    buffer.query = query.new(opened, buffer_reader, function()
      vim.cmd.redrawstatus()
    end)
    M.render(buffer)
    if on_ready then
      on_ready(buffer)
    end
  end)
end

--- Read another sheet of the same workbook.
---@param buffer csv.Buffer
---@param sheet integer 0-based.
function M.open_sheet(buffer, sheet)
  load(buffer, sheet)
end

--- A table is read by scrolling sideways, so wrapping would break every row into
--- a variable number of screen lines and unalign the columns. The gutter draws
--- the row number through `csv-table.buffer.statuscolumn`, which takes the place
--- of the line numbers.
---
--- Each is set through `vim.wo[window][0]`, which is `:setlocal`: the value holds
--- for this buffer in that window alone. `vim.wo[window]` is `:set`, which also
--- writes the value the window keeps for every buffer, and the next buffer shown
--- in the window would inherit it.
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

--- Record the buffer and take over its options and autocommands. The file has
--- not been read, so the query is over an empty file and the page is empty.
---@param bufnr integer
---@param path string
---@return csv.Buffer
local function record(bufnr, path)
  vim.bo[bufnr].buftype = "nowrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local empty = page.empty()
  local buffer = {
    bufnr = bufnr,
    query = query.new(file.empty(path), reader.new(), function()
      vim.cmd.redrawstatus()
    end),
    page = empty,
  }
  buffer.read_state = buffer.query:state(empty)
  buffers[bufnr] = buffer

  set_window_options(bufnr)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      set_window_options(bufnr)
    end,
  })

  -- A motion this plugin leaves to nvim ends here, where the cell the user was
  -- aiming for becomes the active cell.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      if buffers[bufnr] then
        movement.follow_cursor(buffers[bufnr], 0)
      end
      view.remember()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      buffer.query.reader:cancel()
      buffers[bufnr] = nil
      cursor.destroy(bufnr)
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
  -- means refresh. This command owns the whole read, so setting the filetype is
  -- what tells whatever the user hangs off `FileType`.
  vim.bo[bufnr].filetype = "csv-table"

  -- `guicursor` is global, so the buffer that decides it is the one the user is
  -- in. A read can be for a buffer nobody is in, which is what `bufload` does,
  -- and hiding the cursor for that one would hide it where the user is.
  guicursor.update(vim.api.nvim_get_current_buf())

  local buffer = buffers[bufnr]
  if buffer then
    -- nvim empties the buffer before this runs, so the text has to go back
    -- whatever happens. When the file is the one the page was read from, the
    -- lines already in hand are that text, and xan has nothing to add.
    local drawn = buffer.page
    if #drawn.lines > 0 and buffer.query.file:version() == drawn.file_version then
      replace_lines(bufnr, drawn.lines)
      color.redraw(buffer)

      -- The active cell names a row of this page, which is the one still in
      -- hand, so the user comes back to the cell they left.
      local window = vim.fn.bufwinid(bufnr)
      if window ~= -1 then
        view.restore(buffer, window)
      end
      return
    end
  else
    buffer = record(bufnr, path)
  end

  load(buffer, buffer.query.file.sheet, on_ready)
end

return M
