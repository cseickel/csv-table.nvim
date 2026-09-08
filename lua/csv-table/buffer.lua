--[[
Defines `csv.Buffer`, one per buffer: the state the user is building and the
layout of what is on screen.

- `attach` takes over a buffer nvim named after a CSV file
- `render` runs the pipeline and replaces every line
- `open_sheet` reads another sheet of the same workbook
- autocommands keep the view, the visual mode selection and the active cell

The buffer stays nomodifiable. Its text is xan's output, and writing it back
over the file would destroy the file.
]]

local commands = require("csv-table.commands")
local active_cell = require("csv-table.active_cell")
local columns = require("csv-table.columns")
local layout = require("csv-table.layout")
local movement = require("csv-table.movement")
local overlay = require("csv-table.overlay")
local query = require("csv-table.query")
local selection = require("csv-table.selection")
local source = require("csv-table.source")
local statuscolumn = require("csv-table.statuscolumn")
local state = require("csv-table.state")

local M = {}

---@class csv.Buffer
---@field bufnr integer
---@field state csv.State
---@field layout csv.Layout|nil Absent until the first render succeeds.
---@field stamp string|nil What the file looked like when the layout was read.

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

--- Where each window is looking, as `winsaveview` reports it, so a buffer that
--- is emptied and filled again can be put back the way the user left it.
---@type table<integer, table>
local views = {}

--- Keep where the current window is looking. A cursor move and a scroll are
--- the two ways that changes.
local function remember_view()
  views[vim.api.nvim_get_current_win()] = vim.fn.winsaveview()
end

-- `WinScrolled` reports a window rather than a buffer, so it is registered once
-- and asks whether the window it names is showing a table.
vim.api.nvim_create_autocmd("WinScrolled", {
  group = buffer_group,
  callback = function()
    if vim.bo.filetype == "csv-table" then
      remember_view()
    end
  end,
})

-- nvim reuses window handles, so a view left behind would describe the next
-- window to take the number.
vim.api.nvim_create_autocmd("WinClosed", {
  group = buffer_group,
  callback = function(event)
    views[tonumber(event.match)] = nil
  end,
})

-- Entering one of nvim's visual modes is what says the user is picking cells
-- out, whichever key they entered it with. The pattern is the mode nvim came
-- from and the mode it went to, so `\22` is blockwise visual and a switch
-- between two visual modes matches as well.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = buffer_group,
  pattern = "*:[vV\22]",
  callback = function(event)
    local buffer = buffers[vim.api.nvim_get_current_buf()]
    if not buffer or not buffer.layout then
      return
    end

    local was = event.match:match("^(.*):")
    if was == "v" or was == "V" or was == "\22" then
      return movement.change_kind(buffer)
    end
    movement.start_extending(buffer, 0)
  end,
})

-- Leaving a visual mode, where nvim writes `'<` and `'>` from the two ends it
-- was holding. The block the user picked out goes back over them, so `gv`
-- brings the cells back rather than nvim's own rectangle.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = buffer_group,
  pattern = "[vV\22]:*",
  callback = function()
    local buffer = buffers[vim.api.nvim_get_current_buf()]
    if buffer and buffer.layout then
      movement.mark_selection(buffer)
    end
  end,
})

--- Look at `window` the way it was left. The active cell goes back first, so
--- nvim has the cursor on the right line before the view is asked for, and the
--- view then decides which part of the table is on screen.
---
--- Scheduled, because `:edit` puts the cursor on line 1 once the read command
--- it fired has returned, and this has to land after that.
---@param buffer csv.Buffer
---@param window integer
local function restore_view(buffer, window)
  local cell = active_cell.active(buffer, window)
  local view = views[window]

  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_buf(window) ~= buffer.bufnr then
      return
    end

    active_cell.move_to(buffer, window, cell)
    if view then
      vim.api.nvim_win_call(window, function()
        vim.fn.winrestview(view)
      end)
    end
  end)
end

--- What `path` looks like on disk, as a value two reads can be compared by.
--- A file written again in the same second keeps its modification time, so the
--- size comes along.
---@param path string
---@return string|nil nil while the file is out of reach.
local function file_stamp(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  return string.format("%d:%d:%d", stat.size, stat.mtime.sec, stat.mtime.nsec)
end

--- Count the rows the filters leave, once, and keep the answer on the state.
--- The count costs a pass over the file, so it runs when the filters have
--- changed and the statusline has nothing to report.
---@param buffer csv.Buffer
local function count_rows(buffer)
  if buffer.state.row_count then
    return
  end

  local counted = buffer.state
  query.count(buffer.state, query.report, function(count)
    -- The state is replaced when another sheet is opened, so the answer lands
    -- on the state that asked for it.
    counted.row_count = count
    vim.cmd.redrawstatus()
  end)
end

--- Run the pipeline for `buffer` and draw what it returns.
---
--- The selection goes, because a sort changes which rows lie between its two
--- ends, and hiding or moving a column changes which columns those ends name.
---@param buffer csv.Buffer
---@param on_rendered fun()|nil Runs once the new text is in the buffer.
function M.render(buffer, on_rendered)
  selection.clear(buffer.state)

  -- The command and the layout read this one snapshot, so they agree even when
  -- a second render starts while this one is waiting on xan.
  local display_columns = columns.display_columns(buffer.state)
  local first_row_number = state.first_row_number(buffer.state)
  local stamp = file_stamp(buffer.state.source)

  local argv = commands.render(buffer.state, display_columns)
  query.run(argv, query.report, function(stdout)
    if not vim.api.nvim_buf_is_valid(buffer.bufnr) then
      return
    end

    local parsed, err = layout.parse(
      vim.split(stdout, "\n", { plain = true }),
      display_columns,
      first_row_number
    )
    if not parsed then
      return query.report(err)
    end

    -- A page past the first that came back empty is a page past the end, which
    -- happens when the rows divide evenly into pages. Step back and draw the
    -- page that does have rows, so the user sees the view stay where it was.
    if layout.row_count(parsed) < 1 and buffer.state.page > 0 then
      state.turn_page(buffer.state, -1)
      return M.render(buffer, on_rendered)
    end

    buffer.layout = parsed
    buffer.stamp = stamp
    replace_lines(buffer.bufnr, parsed.lines)
    overlay.redraw(buffer)
    -- `status.get_winbar` pins this line while the buffer is scrolled past it.
    vim.b[buffer.bufnr].table_header = parsed.header_line

    local window = vim.fn.bufwinid(buffer.bufnr)
    if window ~= -1 then
      active_cell.restore(buffer, window)
    end

    count_rows(buffer)
    if on_rendered then
      on_rendered()
    end
  end)
end

--- How wide `column` is drawn, in characters, or nil when it is hidden or
--- nothing has been rendered yet.
---@param buffer csv.Buffer
---@param column csv.Column
---@return integer|nil
function M.column_width(buffer, column)
  if not buffer.layout then
    return nil
  end
  local column_number = layout.column_number(buffer.layout, column)
  return column_number and layout.cell_width(buffer.layout, column_number) or nil
end

--- Read another sheet of the same workbook. The filters, sort, marks, column
--- order and formats all name columns of the sheet being left, so the new sheet
--- gets a fresh state.
---@param buffer csv.Buffer
---@param sheet integer 0-based.
function M.open_sheet(buffer, sheet)
  source.inspect(buffer.state.source, sheet, function(source_info)
    if not vim.api.nvim_buf_is_valid(buffer.bufnr) then
      return
    end

    buffer.state = state.new(source_info)
    M.render(buffer)
  end, query.report)
end

--- The rows of the result on display, counting from one.
---@param buffer csv.Buffer
---@return integer first
---@return integer last
function M.row_range(buffer)
  local first = state.first_row_number(buffer.state)
  if not buffer.layout then
    return first, first - 1
  end
  return first, first + layout.row_count(buffer.layout) - 1
end

--- Take over `bufnr`, which nvim has named after a CSV file and left to this
--- plugin to read.
---@param bufnr integer
---@param on_ready fun(buffer: csv.Buffer)|nil
function M.attach(bufnr, on_ready)
  -- `:edit` fires the read command again on a buffer already showing a table,
  -- and means refresh. This command owns the whole read, so setting the
  -- filetype is what tells whatever the user hangs off `FileType`.
  local attached = buffers[bufnr]
  if attached then
    vim.bo[bufnr].filetype = "csv-table"

    -- nvim empties the buffer before this runs, so the text has to go back
    -- whatever happens. When the file is the one the layout was read from, the
    -- lines already in hand are that text, and xan has nothing to add.
    local stamp = file_stamp(attached.state.source)
    if attached.layout and stamp == attached.stamp then
      replace_lines(bufnr, attached.layout.lines)
      overlay.redraw(attached)

      -- The active cell names a row of this layout, which is the one still in
      -- hand, so the user comes back to the cell they left.
      local window = vim.fn.bufwinid(bufnr)
      if window ~= -1 then
        restore_view(attached, window)
      end
      return
    end

    attached.layout = nil
    return M.render(attached)
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return query.report("buffer has no file name")
  end

  vim.bo[bufnr].buftype = "nowrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "csv-table"

  -- A table is read by scrolling sideways, so wrapping would break every row
  -- into a variable number of screen lines and unalign the columns. The gutter
  -- draws the row number through `csv-table.statuscolumn`, which takes the place
  -- of the line numbers.
  --
  -- Each is set through `vim.wo[window][0]`, which is `:setlocal`: the value
  -- holds for this buffer in that window alone. `vim.wo[window]` is `:set`,
  -- which also writes the value the window keeps for every buffer, and the
  -- next buffer shown in the window would inherit it.
  local function set_window_options()
    for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[window][0].wrap = false
      vim.wo[window][0].number = false
      vim.wo[window][0].relativenumber = false
      vim.wo[window][0].signcolumn = "no"
      vim.wo[window][0].statuscolumn = statuscolumn.EXPRESSION
    end
  end
  set_window_options()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = buffer_group,
    buffer = bufnr,
    callback = set_window_options,
  })

  -- A motion this plugin leaves to nvim ends here, where the cell the user was
  -- aiming for becomes the active cell.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if buffer then
        movement.follow_cursor(buffer, 0)
      end
      remember_view()
    end,
  })

  -- `guicursor` is global, so the buffer that decides it is the one the user is
  -- in. A read can be for a buffer nobody is in, which is what `bufload` does,
  -- and hiding the cursor for that one would hide it where the user is.
  active_cell.update_guicursor(vim.api.nvim_get_current_buf())

  source.inspect(path, nil, function(source_info)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local buffer = { bufnr = bufnr, state = state.new(source_info), layout = nil }
    buffers[bufnr] = buffer

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
      group = buffer_group,
      buffer = bufnr,
      callback = function()
        buffers[bufnr] = nil
        active_cell.destroy(bufnr)
      end,
    })

    M.render(buffer)
    if on_ready then
      on_ready(buffer)
    end
  end, query.report)
end

return M
