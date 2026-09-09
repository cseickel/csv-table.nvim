--[[
Tracks the cell the user is on, one per window, with the real cursor hidden and
parked at one edge of that cell.
]]

local color = require("csv-table.buffer.color")

local M = {}

local cell_namespace = vim.api.nvim_create_namespace("csv-active-cell")
local flash_namespace = vim.api.nvim_create_namespace("csv-flash")
local FLASH_MILLISECONDS = 250

--- Characters kept on screen past the active cell, which is what shows the cell's
--- border and a slice of the next column for orientation.
local PREVIEW = 8

---@class csv.ActiveCell
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field ref csv.CellRef
---@field edge "left"|"right" Which end of the cell the cursor is parked at.

--- Keyed by buffer, then by window. The cell belongs to the table, and the window
--- only tells two views of the same table apart.
---@type table<integer, table<integer, csv.ActiveCell>>
local active_cells = {}

--- The cell `ref` names on the page drawn now, absent once the row or the column
--- has left it.
---@param page csv.Page
---@param ref csv.CellRef
---@return csv.Cell|nil
local function resolve(page, ref)
  local row = page:row_by_id(ref.row_id)
  local column = page:column_by_id(ref.column_id)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

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
local function get(buffer, window)
  local windows = active_cells[buffer.bufnr]
  return windows and windows[window_id(window)] or nil
end

--- The last column is set to 0, so the right border is at the edge of the screen
--- and does not scroll past it. Every other column uses the preview value.
---@param buffer csv.Buffer
---@param column_number integer
---@return integer
local function scroll_off(buffer, column_number)
  if column_number == buffer.page:column_count() then
    return 0
  end
  return PREVIEW
end

--- Park the real cursor in the cell and draw it. The cursor takes the last byte
--- of the cell when moving right and the first when moving left, and a move that
--- stays in the same cell keeps the end it had. nvim scrolls sideways only far
--- enough to show the byte the cursor is on, so the far end is what brings the
--- whole cell into view.
---
--- The position recorded is the one nvim reports back, because nvim moves a
--- cursor set inside a multi-byte character to the start of that character.
---@param buffer csv.Buffer
---@param window integer
---@param row csv.Row
---@param column_number integer
local function park_cursor(buffer, window, row, column_number)
  local range = buffer.page:cell_ranges(row.buffer_line)[column_number]
  local column = buffer.page:column_at(column_number)
  if not range or not column then
    return
  end

  -- The column alone, so a render that drops the row still keeps the end the
  -- cursor was parked at.
  local previous = get(buffer, window)
  local previous_column = previous and buffer.page:column_by_id(previous.ref.column_id)
  local was = previous_column and buffer.page:column_number(previous_column)

  local edge = "left"
  if was and column_number > was then
    edge = "right"
  elseif was == column_number then
    edge = previous.edge
  end

  vim.wo[window][0].sidescrolloff = scroll_off(buffer, column_number)
  vim.api.nvim_win_set_cursor(window, {
    row.buffer_line,
    edge == "right" and range.to - 1 or range.from,
  })
  local windows = active_cells[buffer.bufnr] or {}
  active_cells[buffer.bufnr] = windows
  windows[window_id(window)] = {
    position = vim.api.nvim_win_get_cursor(window),
    ref = { row_id = row.row_id, column_id = column.column_id },
    edge = edge,
  }

  -- The highlight is one extmark on the buffer, so it belongs to the window the
  -- user is in. `csv-table.buffer` hands it over on `WinEnter`.
  if window_id(window) == vim.api.nvim_get_current_win() then
    vim.api.nvim_buf_clear_namespace(buffer.bufnr, cell_namespace, 0, -1)
    vim.api.nvim_buf_set_extmark(buffer.bufnr, cell_namespace, row.buffer_line - 1, range.from, {
      end_col = range.to,
      hl_group = "CsvActiveCell",
      priority = color.CELL_PRIORITY,
    })
  end
end

--- Drop every record for `bufnr`, once the buffer is gone. nvim reuses buffer
--- numbers, so a record left behind would describe the next buffer.
---@param bufnr integer
function M.drop_buffer(bufnr)
  active_cells[bufnr] = nil
end

--- Drop what every buffer holds for `window`, once the window is gone. nvim
--- reuses window handles, so a record left behind would describe the next window.
---@param window integer
function M.drop_window(window)
  for _, windows in pairs(active_cells) do
    windows[window] = nil
  end
end

--- Whether the real cursor has left the byte the active cell parked it on, which
--- is what says the user moved it.
---@param buffer csv.Buffer
---@param window integer
---@return boolean
function M.cursor_moved(buffer, window)
  local active = get(buffer, window)
  if not active then
    return true
  end
  local position = vim.api.nvim_win_get_cursor(window)
  return position[1] ~= active.position[1] or position[2] ~= active.position[2]
end

--- The cell the real cursor is in. The cursor is hidden and parked inside the
--- active cell, so this is here to read a move nvim made on its own.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.physical_cell(buffer, window)
  local position = vim.api.nvim_win_get_cursor(window)
  return buffer.page:cell_at(position[1], position[2])
end

--- The cell a move of the real cursor was aiming for.
---
--- A cursor that landed in another cell names that cell, which is what a click, a
--- search or `$` means. A cursor still inside the cell it started in was moved by
--- something too small to leave it, such as `l` in a cell drawn twenty wide, and
--- the cell one step that way is what was meant.
---
--- Sideways is the only direction that can be meant here, so a cursor that kept
--- its byte kept its cell. `k` on the first row of the page is that: the cursor
--- reaches the border line above and `cell_at` brings it back.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.moved_cell(buffer, window)
  local landed = M.physical_cell(buffer, window)
  local active = get(buffer, window)
  if not landed or not active then
    return landed
  end

  local stayed = landed.row.row_id == active.ref.row_id
    and landed.column.column_id == active.ref.column_id
  local byte = vim.api.nvim_win_get_cursor(window)[2]
  if not stayed or byte == active.position[2] then
    return landed
  end

  local columns = byte > active.position[2] and 1 or -1
  return buffer.page:step_cell(landed, { rows = 0, columns = columns })
end

--- The cell that is active in `window`, which is the one drawn in `CsvActiveCell`
--- and the one every action runs on. Absent once its row or column has left the
--- page.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.active_cell(buffer, window)
  local active = get(buffer, window)
  return active and resolve(buffer.page, active.ref) or nil
end

--- Make `cell` active and park the real cursor in it.
---@param buffer csv.Buffer
---@param window integer
---@param cell csv.Cell|nil
---@return csv.Cell|nil
function M.move_to(buffer, window, cell)
  if not cell then
    return nil
  end
  local column_number = buffer.page:column_number(cell.column)
  if not column_number then
    return nil
  end
  park_cursor(buffer, window, cell.row, column_number)
  return cell
end

--- Move the active cell `rows` rows and `columns` columns from where it is.
---@param buffer csv.Buffer
---@param window integer
---@param rows integer
---@param columns integer
---@return csv.Cell|nil
function M.step(buffer, window, rows, columns)
  local cell = M.active_cell(buffer, window)
  if not cell then
    return nil
  end
  return M.move_to(buffer, window, buffer.page:step_cell(cell, { rows = rows, columns = columns }))
end

--- Put the active cell back after a render, taking the row and the column by id,
--- so a sort or a filter that keeps them takes the user along. Either id that has
--- left the page falls back to where the cursor is parked: its line for the row,
--- its byte for the column.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.restore(buffer, window)
  local cell = M.physical_cell(buffer, window)
  local active = get(buffer, window)
  if cell and active then
    cell.row = buffer.page:row_by_id(active.ref.row_id) or cell.row
    cell.column = buffer.page:column_by_id(active.ref.column_id) or cell.column
  end
  return M.move_to(buffer, window, cell)
end

--- The column the active cell is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Column|nil
function M.column(buffer, window)
  local cell = M.active_cell(buffer, window)
  return cell and cell.column or nil
end

--- Highlight one column of every row briefly. A redraw clears extmarks, so this
--- only holds while the text it describes is the text on screen.
---@param buffer csv.Buffer
---@param column csv.Column
function M.flash_column(buffer, column)
  local column_number = buffer.page:column_number(column)
  if not column_number then
    return
  end

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
  local function flash(buffer_line)
    local from, to = buffer.page:cell_bounds(buffer_line, column_number)
    if from then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, flash_namespace, buffer_line - 1, from, {
        end_col = to,
        hl_group = "CsvFlash",
      })
    end
  end

  flash(buffer.page.header_line)
  for buffer_line = buffer.page.first_line, buffer.page.last_line do
    flash(buffer_line)
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buffer.bufnr) then
      vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
    end
  end, FLASH_MILLISECONDS)
end

return M
