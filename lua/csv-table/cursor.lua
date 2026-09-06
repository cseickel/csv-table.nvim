--[[
The active cell.

The cursor is always in a data cell of the rendered table, the way a spreadsheet
always has one active cell: every move lands it in a cell, a move the user makes
onto a border or the row number is snapped into the nearest cell, and the cell is
drawn as the active one while the real cursor is hidden. Every question about
where the cursor is reads that cell.

Every byte offset here comes from `csv-table.layout` for the line the cursor is
on, because a line holding a multi-byte character has its separators at
different byte offsets than the header.

Cell 1 is the row number, so the column under the cursor is cell 2 onwards.
]]

local layout = require("csv-table.layout")
local selection = require("csv-table.selection")

local M = {}

local cell_namespace = vim.api.nvim_create_namespace("csv-cursor")
local flash_namespace = vim.api.nvim_create_namespace("csv-flash")
local FLASH_MILLISECONDS = 250

-- Above `buffer.RANGE_PRIORITY`, so the active cell shows over a selection.
local CELL_PRIORITY = 4300

-- The modes a table buffer is read in. The command line keeps its cursor, so
-- `:`, `/` and every `vim.ui.input` prompt can be typed into.
local HIDDEN_CURSOR = "n-v-o:CsvHiddenCursor"

---@class csv.CursorMark
---@field bufnr integer    The table the window was showing.
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field cell integer
---@field edge "left"|"right" Which end of the cell the cursor is at.

--- Where this plugin last set each window's cursor, so a move it did not make
--- can be told from one it did. A selection survives the moves the plugin makes
--- and is dropped by the ones the user makes. A cursor belongs to a window, so
--- a table shown in two windows has a record for each.
---@type table<integer, csv.CursorMark>
local last_cursor = {}

---@param window integer 0 for the current window, as the API takes it.
---@return integer
local function window_id(window)
  if window == 0 then
    return vim.api.nvim_get_current_win()
  end
  return window
end

---@param buffer csv.Buffer
---@param window integer
---@return csv.CursorMark|nil
local function last_cursor_in(buffer, window)
  local last = last_cursor[window_id(window)]
  if last and last.bufnr == buffer.bufnr then
    return last
  end
  return nil
end

--- How many cells a line of the table holds, the row number counted.
---@param buffer csv.Buffer
---@return integer
local function cell_count(buffer)
  return #selection.display_columns(buffer.state) + 1
end

--- How far past the cursor the screen is kept scrolled: the row number cell and
--- the borders either side of it, so the first column always shows the row
--- number and the table's left edge, and every other column shows that much of
--- its neighbor. The row number is digits and padding, so its bytes are its
--- columns. In the last column nothing is kept, or the screen would scroll past
--- the table's right edge into blank space.
---@param buffer csv.Buffer
---@param cell integer
---@param ranges csv.CellRange[]
---@return integer
local function scroll_off(buffer, cell, ranges)
  if cell == cell_count(buffer) then
    return 0
  end
  return ranges[1].to - ranges[1].from + 2
end

--- Put the cursor in cell `cell` of `line` and draw it as the active one.
---
--- nvim scrolls sideways only far enough to show the byte the cursor is on, so
--- the cursor goes to the far end of the cell in the direction of travel: the
--- last byte when moving right, the first when moving left. A move that stays
--- in the same cell keeps the end it had. 'sidescrolloff' then shows the border
--- and beyond it.
---
--- The position recorded is the one nvim reports back rather than the one
--- asked for, because nvim moves a cursor set inside a multi-byte character to
--- the start of that character.
---@param buffer csv.Buffer
---@param window integer
---@param line integer
---@param cell integer
---@param ranges csv.CellRange[] The cells of `line`.
local function set_cursor(buffer, window, line, cell, ranges)
  local previous = last_cursor_in(buffer, window)
  local edge = previous and previous.edge or "left"
  if previous and cell > previous.cell then
    edge = "right"
  elseif previous and cell < previous.cell then
    edge = "left"
  end

  local range = ranges[cell]
  vim.wo[window][0].sidescrolloff = scroll_off(buffer, cell, ranges)
  vim.api.nvim_win_set_cursor(window, { line, edge == "right" and range.to - 1 or range.from })
  last_cursor[window_id(window)] = {
    bufnr = buffer.bufnr,
    position = vim.api.nvim_win_get_cursor(window),
    cell = cell,
    edge = edge,
  }

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, cell_namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer.bufnr, cell_namespace, line - 1, range.from, {
    end_col = range.to,
    hl_group = "CsvCursorCell",
    priority = CELL_PRIORITY,
  })
end

--- Drop the record for `bufnr`, once the buffer is gone. nvim reuses buffer
--- numbers, so a record left behind would describe the next buffer.
---@param bufnr integer
function M.forget(bufnr)
  for window, last in pairs(last_cursor) do
    if last.bufnr == bufnr then
      last_cursor[window] = nil
    end
  end
end

--- Whether the cursor is where this plugin last set it.
---@param buffer csv.Buffer
---@param window integer
---@return boolean
function M.is_ours(buffer, window)
  local last = last_cursor_in(buffer, window)
  if not last then
    return false
  end
  local position = vim.api.nvim_win_get_cursor(window)
  return position[1] == last.position[1] and position[2] == last.position[2]
end

--- Which line and cell the cursor is in, both clamped into the table, so a
--- cursor resting on a border, the row number, or a rule answers with the
--- nearest cell it could act on.
---@param buffer csv.Buffer
---@param window integer
---@return integer line
---@return integer cell
local function cell_under_cursor(buffer, window)
  local position = vim.api.nvim_win_get_cursor(window)
  local first, last = buffer.layout.first_row, buffer.layout.last_row
  local line = math.min(math.max(position[1], first), last)
  local cell = layout.cell_at(buffer.layout, line, position[2])
  return line, math.min(math.max(cell, 2), cell_count(buffer))
end

--- Put the cursor on a cell named by line and cell number, both clamped, and
--- say which cell of the table that turned out to be.
---@param buffer csv.Buffer
---@param window integer
---@param line integer
---@param cell integer
---@return csv.CellRef|nil
function M.move_to(buffer, window, line, cell)
  if not buffer.layout or buffer.layout.first_row > buffer.layout.last_row then
    return nil
  end

  line = math.min(math.max(line, buffer.layout.first_row), buffer.layout.last_row)
  cell = math.min(math.max(cell, 2), cell_count(buffer))

  local ranges = layout.cell_ranges(buffer.layout, line)
  if not ranges[cell] then
    return nil
  end

  set_cursor(buffer, window, line, cell, ranges)
  local rowid = buffer.layout.rowids[line]
  if not rowid then
    return nil
  end
  return { row = rowid, column = cell - 1 }
end

--- Move the cursor `rows` lines and `cells` cells from where it is.
---@param buffer csv.Buffer
---@param window integer
---@param rows integer
---@param cells integer
---@return csv.CellRef|nil
function M.step(buffer, window, rows, cells)
  if not buffer.layout then
    return nil
  end
  local line, cell = cell_under_cursor(buffer, window)
  return M.move_to(buffer, window, line + rows, cell + cells)
end

--- Put the cursor in the nearest cell to wherever a move the plugin did not
--- make has left it.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.snap(buffer, window)
  return M.step(buffer, window, 0, 0)
end

--- Put the cursor back in the cell it was in before a render. The new text has
--- its own column widths, so the byte the cursor is on may now be in another
--- cell, and the cell number is what says where the user was. Before this plugin
--- has set a cursor, the first row and column.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.restore(buffer, window)
  if not buffer.layout then
    return nil
  end
  local last = last_cursor_in(buffer, window)
  local line = vim.api.nvim_win_get_cursor(window)[1]
  return M.move_to(buffer, window, line, last and last.cell or 2)
end

--- Which cell of the table the cursor is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.cell_ref(buffer, window)
  if not buffer.layout then
    return nil
  end
  local line, cell = cell_under_cursor(buffer, window)
  local rowid = buffer.layout.rowids[line]
  if not rowid then
    return nil
  end
  return { row = rowid, column = cell - 1 }
end

--- The column under the cursor, or nil before the first render.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Column|nil
function M.column_at(buffer, window)
  local cell = M.cell_ref(buffer, window)
  return cell and selection.display_columns(buffer.state)[cell.column] or nil
end

--- Highlight one cell of every row briefly. A redraw clears extmarks, so this
--- only holds while the text it describes is the text on screen.
---@param buffer csv.Buffer
---@param cell integer
function M.flash_cell(buffer, cell)
  if not buffer.layout then
    return
  end

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
  local function flash(index)
    local from, to = layout.cell_bounds(buffer.layout, index, cell)
    if from then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, flash_namespace, index - 1, from, {
        end_col = to,
        hl_group = "CsvFlash",
      })
    end
  end

  flash(buffer.layout.header)
  for index = buffer.layout.first_row, buffer.layout.last_row do
    flash(index)
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buffer.bufnr) then
      vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
    end
  end, FLASH_MILLISECONDS)
end

--- `guicursor` without the entry this plugin appends, which is the value it
--- held before a table hid the cursor. The entry is dropped from the list
--- rather than cut out of the string, because cutting it out would leave the
--- comma beside it, and nvim rejects an empty entry.
---@param value string
---@return string
local function without_hidden(value)
  local entries = {}
  for _, entry in ipairs(vim.split(value, ",", { plain = true })) do
    if entry ~= HIDDEN_CURSOR then
      entries[#entries + 1] = entry
    end
  end
  return table.concat(entries, ",")
end

--- Hide the real cursor if `bufnr` holds a table and show it if it does not.
--- The active cell is what shows where the cursor is in a table.
---
--- `guicursor` is global and holds one entry per mode, the last entry for a
--- mode winning, so hiding is appending an entry and showing is taking that
--- entry back out. Nothing is stored between the two: taking the entry out
--- rebuilds the value that was there before, and a value this plugin never
--- added to comes back unchanged, so another plugin styling the cursor its own
--- way is left alone.
---@param bufnr integer
function M.update_guicursor(bufnr)
  local base = without_hidden(vim.o.guicursor)
  local setting = base
  if vim.bo[bufnr].filetype == "csv-table" then
    setting = base == "" and HIDDEN_CURSOR or base .. "," .. HIDDEN_CURSOR
  end
  if setting ~= vim.o.guicursor then
    vim.o.guicursor = setting
  end
end

--- Follow the cursor's visibility for the rest of the session.
---
--- Entering a buffer is the only event that decides it. Undoing the hide on
--- leaving instead would hold for every buffer after a leave that is missed,
--- and a leave is missed by a buffer wiped while it is current or by a window
--- opened with `noautocmd`. Decided on entry, a missed event lasts until the
--- next entry rather than for the session.
---@param group integer
function M.setup(group)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      M.update_guicursor(event.buf)
    end,
  })
end

return M
