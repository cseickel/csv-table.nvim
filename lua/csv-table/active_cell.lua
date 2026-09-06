--[[
This module emulates the concept of cell movement and maintains the active cell.
The real cursor is hidden and snapped into a specific edge of a cell, so any movement
can be detected and translated into cell movements.

This module:

1. Draws the active cell
2. Intercepts nvim native character wise movements and translates them into cell movements
3. Handles programmatic cell movement
4. Provides information about the active cell and where the real cursor is parked within it

Column 1 is the row number and is a decoration instead of a data cell, so focus is restricted
to column 2 onwards.
]]

local layout = require("csv-table.layout")
local range = require("csv-table.range")
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

---@class csv.ActiveCell
---@field bufnr integer    The table the window was showing.
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field row_number integer
---@field column_number integer
---@field edge "left"|"right" Which end of the cell the cursor is at.

---@type table<integer, csv.ActiveCell>
local active_cell = {}

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
---@return csv.ActiveCell|nil
local function get_active_cell(buffer, window)
  local last = active_cell[window_id(window)]
  if last and last.bufnr == buffer.bufnr then
    return last
  end
  return nil
end

--- How many columns in the table, including with the row number.
---@param buffer csv.Buffer
---@return integer
local function column_count(buffer)
  return #selection.display_columns(buffer.state) + 1
end

--- This is calculate per column because the desired value is different
--- depending on the region:
---
--- A. When at the left edge, this value is set to the width of the row number
---    column. This prevents the cursor from entering that column and stops the
---    scroll at the correct position.
--- B. When in the middle region we want a comfortable preview of the next column
---    to the right for orientation. The row number column width is fine for this
---    purpose as well, so we don't need to handle it differently.
--- C. When at the right edge, we want to stop the scroll so the right most border 
---    is shown at the edge of the screen and we never show blank space past that. 
---
--- So in the end, it is either at the right most column (C) and scroll off is
--- 0, or any other position (A or B) and the scroll off is the width of the
--- row number column.
---
--- We may change that to add an explicit value for B in the future.
---@param buffer csv.Buffer
---@param column_num integer
---@return integer
local function scroll_off(buffer, column_num)
  if column_num == column_count(buffer) then
    return 0
  end
  local first_col = buffer.layout.ranges[1]
  return first_col.to - first_col.from + 2
end

--- Set the active cell to `cell` of `line`.
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
---@param row_number integer
---@param column_number integer
local function set_cursor(buffer, window, row_number, column_number)
  local row = layout.get_row(buffer.layout, row_number)
  if not row[column_number] then
    return nil
  end
  local cell = row[column_number]

  local edge = "left"
  local previous = get_active_cell(buffer, window)
  if previous then
    if column_number > previous.column_number then
      edge = "right"
    elseif column_number < previous.column_number then
      edge = "left"
    else
      edge = previous.edge or "left"
    end
  end

  vim.wo[window][0].sidescrolloff = scroll_off(buffer, column_number)
  vim.api.nvim_win_set_cursor(window, { row_number, edge == "right" and cell.to - 1 or cell.from })
  active_cell[window_id(window)] = {
    bufnr = buffer.bufnr,
    position = vim.api.nvim_win_get_cursor(window),
    row_number = row_number,
    column_number = column_number,
    edge = edge,
  }

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, cell_namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer.bufnr, cell_namespace, row_number - 1, cell.from, {
    end_col = cell.to,
    hl_group = "CsvCursorCell",
    priority = CELL_PRIORITY,
  })
end

--- Drop the record for `bufnr`, once the buffer is gone. nvim reuses buffer
--- numbers, so a record left behind would describe the next buffer.
---@param bufnr integer
function M.destroy(bufnr)
  for window, last in pairs(active_cell) do
    if last.bufnr == bufnr then
      active_cell[window] = nil
    end
  end
end

--- Handles manual movement of the cursor and translates it to cell movement.
---@param buffer csv.Buffer
---@param window integer
---@return boolean
function M.cursor_moved(buffer, window)
  local last = get_active_cell(buffer, window)
  if not last then
    return false
  end
  local position = vim.api.nvim_win_get_cursor(window)
  local not_moved = position[1] == last.position[1] and position[2] == last.position[2]
  if not not_moved then
    return false
  end
  M.snap(buffer, 0)
  if buffer.state.range then
    range.clear(buffer.state)
    M.redraw(buffer)
  end
  return true
end

local function clamp_position_to_layout(buffer, row_number, column_number)
  local first, last = buffer.layout.first_row, buffer.layout.last_row
  row_number = math.min(math.max(row_number, first), last)
  column_number = math.min(math.max(column_number, 2), buffer.layout.column_count)
  return row_number, column_number
end

--- The row/column coordinates of the real nvim cursor.
---@param buffer csv.Buffer
---@param window integer
---@return integer line
---@return integer cell
local function cell_nearest_cursor(buffer, window)
  local position = vim.api.nvim_win_get_cursor(window)
  local row_number = position[1]
  local column_number = layout.cell_at(buffer.layout, row_number, position[2])
  return clamp_position_to_layout(buffer, row_number, column_number)
end

--- Attempt to set the active cell to `column_number` of `row_number`.
--- If that is out of bounds, the nearest cell is chosen. The result is
--- returned as a cell reference.
---@param buffer csv.Buffer
---@param window integer
---@param line integer
---@param cell integer
---@return csv.CellRef|nil
function M.move_to(buffer, window, line, cell)
  if not buffer.layout or buffer.layout.first_row > buffer.layout.last_row then
    return nil
  end

  local row_number, column_number = clamp_position_to_layout(buffer, line, cell)

  set_cursor(buffer, window, row_number, column_number)
  local rowid = buffer.layout.row_id_by_index[row_number]
  if not rowid then
    return nil
  end
  -- WGY is column -1? Is the 0 based?
  -- rowid should not be named row, it is ambiguous
  return { row = rowid, column = column_number - 1 }
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
  local line, cell = cell_nearest_cursor(buffer, window)
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
  local last = get_active_cell(buffer, window)
  local line = vim.api.nvim_win_get_cursor(window)[1]
  return M.move_to(buffer, window, line, last and last.column_number or 2)
end

--- Which cell of the table the cursor is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.CellRef|nil
function M.cell_ref(buffer, window)
  if not buffer.layout then
    return nil
  end
  local line, cell = cell_nearest_cursor(buffer, window)
  local rowid = buffer.layout.row_id_by_index[line]
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
