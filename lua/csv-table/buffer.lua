--[[
The buffer a CSV is shown in.

Owns one record per buffer, holding the state the user is building and the
layout of what is currently on screen. Rendering runs the pipeline and replaces
every line, so the layout is rebuilt on each render and nothing derived from it
outlives the text it describes.

The buffer stays nomodifiable. Its text is xan's output, not a document.
]]

local commands = require("csv-table.commands")
local active_cell = require("csv-table.active_cell")
local layout = require("csv-table.layout")
local query = require("csv-table.query")
local range = require("csv-table.range")
local selection = require("csv-table.selection")
local source = require("csv-table.source")
local state = require("csv-table.state")

local M = {}

---@class csv.Buffer
---@field bufnr integer
---@field state csv.State
---@field layout csv.Layout|nil Absent until the first render succeeds.

---@type table<integer, csv.Buffer>
local buffers = {}

local mark_namespace = vim.api.nvim_create_namespace("csv-marks")

-- The autocommands a table buffer owns. Kept out of the group `setup` clears,
-- because these belong to one buffer: nvim drops them with the buffer, and a
-- second `setup` would take them from the tables already open.
local buffer_group = vim.api.nvim_create_augroup("csv-table-buffer", { clear = false })

-- Above the 4096 an extmark takes by default, so a selected cell draws over the
-- row highlight it may be sitting on.
local RANGE_PRIORITY = 4200

--- Draw the marked rows and the marked columns.
---@param buffer csv.Buffer
local function draw_marks(buffer)
  for line = buffer.layout.first_row, buffer.layout.last_row do
    local rowid = buffer.layout.row_id_by_index[line]
    if rowid and buffer.state.marked[rowid] then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, mark_namespace, line - 1, 0, {
        line_hl_group = "CsvMarkedRow",
      })
    end
  end

  local header = buffer.layout.header
  for position, column in ipairs(selection.display_columns(buffer.state)) do
    if buffer.state.marked_columns[column.index] then
      local from, to = layout.cell_bounds(buffer.layout, header, position + 1)
      if from then
        vim.api.nvim_buf_set_extmark(buffer.bufnr, mark_namespace, header - 1, from, {
          end_col = to,
          hl_group = "CsvMarkedColumn",
        })
      end
    end
  end
end

--- Draw the selected cells. The columns of a range are next to each other, so
--- each line takes one extmark from the left edge of the first to the right
--- edge of the last. The priority puts it over a marked row, which is the whole
--- line and the less specific of the two.
---@param buffer csv.Buffer
local function draw_range(buffer)
  local bounds = range.bounds(buffer.state, buffer.layout)
  if not bounds then
    return
  end

  for line = bounds.top, bounds.bottom do
    local cells = layout.get_row(buffer.layout, line)
    local first, last = cells[bounds.left + 1], cells[bounds.right + 1]
    if first and last then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, mark_namespace, line - 1, first.from, {
        end_col = last.to,
        hl_group = "CsvSelection",
        priority = RANGE_PRIORITY,
      })
    end
  end
end

--- Draw the marks and the selection over the text already in the buffer.
--- Marking a row and selecting a cell change nothing xan would return, so both
--- redraw and neither asks for the page again.
---@param buffer csv.Buffer
function M.redraw(buffer)
  if not buffer.layout then
    return
  end
  vim.api.nvim_buf_clear_namespace(buffer.bufnr, mark_namespace, 0, -1)
  draw_marks(buffer)
  draw_range(buffer)
end

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

--- Run the pipeline for `buffer` and draw what it returns.
---
--- The selection goes. A sort changes which rows lie between its two ends, and
--- hiding or moving a column changes which columns its two ends name, so a
--- selection that outlived a render would mean cells the user never picked.
---
--- The cursor goes back to the cell it was in, because the new text has its
--- own column widths, and the first render finds it at the top of the buffer.
---@param buffer csv.Buffer
---@param on_rendered fun()|nil Runs once the new text is in the buffer.
function M.render(buffer, on_rendered)
  range.clear(buffer.state)

  query.run(commands.render(buffer.state), query.report, function(stdout)
    if not vim.api.nvim_buf_is_valid(buffer.bufnr) then
      return
    end

    local parsed, err = layout.parse(vim.split(stdout, "\n", { plain = true }))
    if not parsed then
      return query.report(err)
    end

    buffer.layout = parsed
    replace_lines(buffer.bufnr, parsed.lines)
    M.redraw(buffer)
    -- `status.get_winbar` pins this line while the buffer is scrolled past it.
    vim.b[buffer.bufnr].table_header = parsed.header

    local window = vim.fn.bufwinid(buffer.bufnr)
    if window ~= -1 then
      active_cell.restore(buffer, window)
    end

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
  local position = selection.position(buffer.state, column)
  if not buffer.layout or not position then
    return nil
  end
  return layout.cell_width(buffer.layout, position + 1)
end

--- Read another sheet of the same workbook. The filters, sort, marks, column
--- selection and formats all name columns of the sheet being left, so the view
--- starts clean rather than pointing them at columns that may not exist.
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

--- Whether the rendered page is the last one, which is true when it came back
--- short. Nothing counts the rows a filter matches, so a short page is the only
--- signal that paging further would show an empty table.
---@param buffer csv.Buffer
---@return boolean
function M.at_last_page(buffer)
  if not buffer.layout then
    return false
  end
  return layout.row_count(buffer.layout) < buffer.state.limit
end

--- Take over `bufnr`, which nvim has named after a CSV file but has not read.
--- The table replaces the file's text, so the buffer is `nowrite`: writing the
--- rendered table back over the source would destroy it.
---@param bufnr integer
---@param on_ready fun(buffer: csv.Buffer)|nil
function M.attach(bufnr, on_ready)
  -- `:edit` fires the read command again on a buffer already showing a table,
  -- and means refresh rather than attach. This command replaces the whole read,
  -- so `BufRead` never fires and filetype detection never runs. Setting the
  -- filetype announces it again to whatever the user hangs off `FileType`.
  local attached = buffers[bufnr]
  if attached then
    vim.bo[bufnr].filetype = "csv-table"
    -- nvim has already emptied the buffer, so the layout describes text that is
    -- gone and the next render is a whole xan run away.
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
  -- into a variable number of screen lines and unalign the columns. Line
  -- numbers go too, since column one of the table is the row number.
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
    end
  end
  set_window_options()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = buffer_group,
    buffer = bufnr,
    callback = set_window_options,
  })

  -- Handle manual movement of the cursor and translate it to cell movement.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = buffer_group,
    buffer = bufnr,
    callback = function()
      local buffer = buffers[bufnr]
      if not buffer or not buffer.layout then
        return
      end
      active_cell.cursor_moved(buffer, 0)
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
