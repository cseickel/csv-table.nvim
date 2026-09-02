--[[
The active cell.

The cursor is always in a data cell of the painted table, the way a spreadsheet
always has one active cell: every move lands it in a cell, a move the user makes
onto a border or the row id is snapped into the nearest cell, and the cell is
painted as the active one while the real cursor is hidden. Every question about
where the cursor is reads that cell.

Every byte offset here comes from `csv-table.layout` for the line the cursor is
on, because a line holding a multi-byte character has its separators at
different byte offsets than the header.

Cell 1 is the row id, so the column under the cursor is cell 2 onwards.
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

---@class csv.Placed
---@field bufnr integer    The table the window was showing.
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field cell integer
---@field edge "left"|"right" Which end of the cell the cursor is at.

--- Where this plugin last put each window's cursor, so a move it did not make
--- can be told from one it did. A selection survives the moves the plugin makes
--- and is dropped by the ones the user makes. A cursor belongs to a window, so
--- a table shown in two windows has a record for each.
---@type table<integer, csv.Placed>
local placed = {}

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
---@return csv.Placed|nil
local function placed_in(buffer, window)
  local at = placed[window_id(window)]
  if at and at.bufnr == buffer.bufnr then
    return at
  end
  return nil
end

--- How many cells a line of the table holds, the row id counted.
---@param buffer csv.Buffer
---@return integer
local function cell_count(buffer)
  return #selection.selected(buffer.state) + 1
end

--- How far past the cursor the screen is kept scrolled: the row id cell and the
--- borders either side of it, so the first column always shows the row id and
--- the table's left edge, and every other column shows that much of its
--- neighbour. The row id is digits and padding, so its bytes are its columns.
--- In the last column nothing is kept, or the screen would scroll past the
--- table's right edge into blank space.
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

--- Put the cursor in cell `cell` of `line` and paint it as the active one.
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
local function place(buffer, window, line, cell, ranges)
  local previous = placed_in(buffer, window)
  local edge = previous and previous.edge or "left"
  if previous and cell > previous.cell then
    edge = "right"
  elseif previous and cell < previous.cell then
    edge = "left"
  end

  local range = ranges[cell]
  vim.wo[window].sidescrolloff = scroll_off(buffer, cell, ranges)
  vim.api.nvim_win_set_cursor(window, { line, edge == "right" and range.to - 1 or range.from })
  placed[window_id(window)] = {
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

--- Drop what is held for `bufnr`, once the buffer is gone. nvim reuses buffer
--- numbers, so a record left behind would describe the next buffer.
---@param bufnr integer
function M.forget(bufnr)
  for window, at in pairs(placed) do
    if at.bufnr == bufnr then
      placed[window] = nil
    end
  end
end

--- Whether the cursor is where this plugin last put it.
---@param buffer csv.Buffer
---@param window integer
---@return boolean
function M.is_placed(buffer, window)
  local at = placed_in(buffer, window)
  if not at then
    return false
  end
  local position = vim.api.nvim_win_get_cursor(window)
  return position[1] == at.position[1] and position[2] == at.position[2]
end

--- Which line and cell the cursor is in, both clamped into the table, so a
--- cursor resting on a border, the row id, or a rule answers with the nearest
--- cell it could act on.
---@param buffer csv.Buffer
---@param window integer
---@return integer line
---@return integer cell
local function clamped(buffer, window)
  local painted = buffer.layout
  local position = vim.api.nvim_win_get_cursor(window)
  local line = math.min(math.max(position[1], painted.first_row), painted.last_row)
  local cell = layout.cell_near(painted, line, position[2])
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
  local painted = buffer.layout
  if not painted or painted.first_row > painted.last_row then
    return nil
  end

  line = math.min(math.max(line, painted.first_row), painted.last_row)
  cell = math.min(math.max(cell, 2), cell_count(buffer))

  local ranges = layout.cell_ranges(painted, line)
  if not ranges[cell] then
    return nil
  end

  place(buffer, window, line, cell, ranges)
  local rowid = painted.rowids[line]
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
  local line, cell = clamped(buffer, window)
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

--- Put the cursor back in the cell it was in before a repaint. The new text
--- has its own column widths, so the byte the cursor is on may now be in
--- another cell, and the cell number is what says where the user was. Before
--- anything has been placed, the first row and column.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.restore(buffer, window)
  if not buffer.layout then
    return nil
  end
  local at = placed_in(buffer, window)
  local line = vim.api.nvim_win_get_cursor(window)[1]
  return M.move_to(buffer, window, line, at and at.cell or 2)
end

--- Which cell of the table the cursor is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.cell_ref(buffer, window)
  if not buffer.layout then
    return nil
  end
  local line, cell = clamped(buffer, window)
  local rowid = buffer.layout.rowids[line]
  if not rowid then
    return nil
  end
  return { row = rowid, column = cell - 1 }
end

--- The column under the cursor, or nil before the first paint.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Column|nil
function M.column_at(buffer, window)
  local cell = M.cell_ref(buffer, window)
  return cell and selection.selected(buffer.state)[cell.column] or nil
end

--- Highlight one cell of every row briefly. Repainting clears extmarks, so this
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

--- The `guicursor` in force before a table buffer hid the cursor, so leaving
--- the buffer can put it back. `guicursor` is global, so it is swapped on
--- entering and leaving rather than set once.
---@type string|nil
local shown_cursor = nil

--- A later entry for a mode wins, so the hidden cursor is appended to what the
--- user has rather than replacing it, and every other mode keeps its shape.
local function hide_cursor()
  if not shown_cursor then
    shown_cursor = vim.o.guicursor
  end
  if shown_cursor == "" then
    vim.o.guicursor = HIDDEN_CURSOR
  else
    vim.o.guicursor = shown_cursor .. "," .. HIDDEN_CURSOR
  end
end

local function show_cursor()
  if shown_cursor then
    vim.o.guicursor = shown_cursor
    shown_cursor = nil
  end
end

--- Hide the real cursor while `bufnr` is the current buffer. The painted cell
--- is what shows where the cursor is.
---@param bufnr integer
function M.hide(bufnr)
  vim.api.nvim_create_autocmd("BufEnter", { buffer = bufnr, callback = hide_cursor })
  vim.api.nvim_create_autocmd("BufLeave", { buffer = bufnr, callback = show_cursor })
  if vim.api.nvim_get_current_buf() == bufnr then
    hide_cursor()
  end
end

return M
