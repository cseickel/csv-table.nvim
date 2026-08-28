--[[
Where the cursor sits in the painted table.

Every question here is answered from the line the cursor is on, never from the
header, because `xan view` pads cells to display width and a line holding a
multi-byte character puts its separators at different byte offsets.

Cell 1 is the row id, so the column under the cursor is cell 2 onwards.
]]

local layout = require("csv-table.layout")
local selection = require("csv-table.selection")

local M = {}

local flash_namespace = vim.api.nvim_create_namespace("csv-flash")
local FLASH_MILLISECONDS = 250

--- Where this plugin last put each buffer's cursor, so a move it did not make
--- can be told from one it did. A selection survives the moves the plugin makes
--- and is dropped by the ones the user makes.
---@type table<integer, integer[]>
local placed = {}

---@param buffer csv.Buffer
---@param window integer
---@param position integer[] Line and byte column, as nvim reports a cursor.
local function place(buffer, window, position)
  vim.api.nvim_win_set_cursor(window, position)
  placed[buffer.bufnr] = position
end

--- Whether the cursor is where this plugin last put it.
---@param buffer csv.Buffer
---@param window integer
---@return boolean
function M.is_placed(buffer, window)
  local at = placed[buffer.bufnr]
  if not at then
    return false
  end
  local position = vim.api.nvim_win_get_cursor(window)
  return position[1] == at[1] and position[2] == at[2]
end

--- Put the cursor in `cell` without changing which line it is on.
---@param buffer csv.Buffer
---@param window integer
---@param cell integer
function M.focus_cell(buffer, window, cell)
  if not buffer.layout then
    return
  end

  local position = vim.api.nvim_win_get_cursor(window)
  local line = buffer.layout.lines[position[1]]
  local from = line and layout.cell_bounds(line, cell)
  if from then
    place(buffer, window, { position[1], from + 1 })
  end
end

--- Put the cursor on the first data row, past the row id, so it starts on a
--- cell the column actions can act on.
---@param buffer csv.Buffer
function M.focus_first_row(buffer)
  local painted = buffer.layout
  if not painted or painted.first_row > painted.last_row then
    return
  end

  local window = vim.fn.bufwinid(buffer.bufnr)
  if window == -1 then
    return
  end

  place(buffer, window, { painted.first_row, 0 })
  M.focus_cell(buffer, window, 2)
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
  for index = buffer.layout.header, buffer.layout.last_row do
    local from, to = layout.cell_bounds(buffer.layout.lines[index], cell)
    if from then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, flash_namespace, index - 1, from, {
        end_col = to,
        hl_group = "CsvFlash",
      })
    end
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buffer.bufnr) then
      vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
    end
  end, FLASH_MILLISECONDS)
end

--- How many cells a line of the table holds, the row id counted.
---@param buffer csv.Buffer
---@return integer
local function cell_count(buffer)
  return #selection.selected(buffer.state) + 1
end

--- Which line and cell the cursor is in, both clamped into the table, so a
--- cursor resting on a border or the row id answers with the nearest cell it
--- could act on.
---@param buffer csv.Buffer
---@param window integer
---@return integer line
---@return integer cell
local function clamped(buffer, window)
  local painted = buffer.layout
  local position = vim.api.nvim_win_get_cursor(window)
  local line = math.min(math.max(position[1], painted.first_row), painted.last_row)
  local cell = layout.cell_at(painted.lines[line], position[2]) or 2
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

  local from = layout.cell_bounds(painted.lines[line], cell)
  if not from then
    return nil
  end

  place(buffer, window, { line, from + 1 })
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

--- The column under the cursor, or nil when the cursor is on the row id, a
--- border, or past the last column.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Column|nil
function M.column_at(buffer, window)
  if not buffer.layout then
    return nil
  end

  local position = vim.api.nvim_win_get_cursor(window)
  local line = buffer.layout.lines[position[1]]
  if not line then
    return nil
  end

  local cell = layout.cell_at(line, position[2])
  if not cell or cell < 2 then
    return nil
  end
  return selection.selected(buffer.state)[cell - 1]
end

--- Move the cursor one column left or right.
---@param buffer csv.Buffer
---@param window integer
---@param delta integer
function M.jump_column(buffer, window, delta)
  if not buffer.layout then
    return
  end

  local position = vim.api.nvim_win_get_cursor(window)
  local line = buffer.layout.lines[position[1]]
  if not line then
    return
  end
  M.focus_cell(buffer, window, (layout.cell_at(line, position[2]) or 1) + delta)
end

--- The source row id under the cursor, or nil when the cursor is not on a row.
---@param buffer csv.Buffer
---@param window integer
---@return integer|nil
function M.rowid_at(buffer, window)
  if not buffer.layout then
    return nil
  end

  local position = vim.api.nvim_win_get_cursor(window)
  return buffer.layout.rowids[position[1]]
end

return M
