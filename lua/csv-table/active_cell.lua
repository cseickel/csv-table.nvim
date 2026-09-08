--[[
The cell the user is on, and the movement between cells.

The real cursor is hidden and parked at one edge of the active cell, so any
movement nvim reports is a movement the user made, and this module translates it
back into a cell.

The edge is the direction of travel: nvim scrolls sideways only far enough to
show the byte the cursor is on, so parking at the far end of the cell is what
brings the whole cell into view.
]]

local layout_module = require("csv-table.layout")

local M = {}

local cell_namespace = vim.api.nvim_create_namespace("csv-active-cell")
local flash_namespace = vim.api.nvim_create_namespace("csv-flash")
local FLASH_MILLISECONDS = 250

-- Above `overlay.SELECTION_PRIORITY`, so the active cell shows over a selection.
local CELL_PRIORITY = 4300

-- The modes a table buffer is read in. The command line keeps its cursor, so
-- `:`, `/` and every `vim.ui.input` prompt can be typed into.
local HIDDEN_CURSOR = "n-v-o:CsvHiddenCursor"

---@class csv.ActiveCell
---@field bufnr integer
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field row csv.Row
---@field column csv.Column
---@field edge "left"|"right" Which end of the cell the cursor is parked at.

---@type table<integer, csv.ActiveCell>
local active_cells = {}

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
  local active = active_cells[window_id(window)]
  if active and active.bufnr == buffer.bufnr then
    return active
  end
  return nil
end

--- Characters kept on screen past the active cell, which is what shows the
--- cell's border and a slice of the next column for orientation.
local PREVIEW = 8

--- The last column is set to 0, so the right border is at the edge of the
--- screen and does not scroll past it. Every other column uses the preview
--- value.
---@param buffer csv.Buffer
---@param column_number integer
---@return integer
local function scroll_off(buffer, column_number)
  if column_number == layout_module.column_count(buffer.layout) then
    return 0
  end
  return PREVIEW
end

--- Park the real cursor in the cell and draw it. The cursor takes the last byte
--- of the cell when moving right and the first when moving left, and a move
--- that stays in the same cell keeps the end it had.
---
--- The position recorded is the one nvim reports back, because nvim moves a
--- cursor set inside a multi-byte character to the start of that character.
---@param buffer csv.Buffer
---@param window integer
---@param row csv.Row
---@param column_number integer
local function park_cursor(buffer, window, row, column_number)
  local range = layout_module.cell_ranges(buffer.layout, row.buffer_line)[column_number]
  if not range then
    return
  end

  local edge = "left"
  local previous = get(buffer, window)
  if previous then
    local was = layout_module.column_number(buffer.layout, previous.column)
    if was and column_number > was then
      edge = "right"
    elseif was and column_number == was then
      edge = previous.edge
    end
  end

  vim.wo[window][0].sidescrolloff = scroll_off(buffer, column_number)
  vim.api.nvim_win_set_cursor(window, {
    row.buffer_line,
    edge == "right" and range.to - 1 or range.from,
  })
  active_cells[window_id(window)] = {
    bufnr = buffer.bufnr,
    position = vim.api.nvim_win_get_cursor(window),
    row = row,
    column = layout_module.column_at(buffer.layout, column_number),
    edge = edge,
  }

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, cell_namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer.bufnr, cell_namespace, row.buffer_line - 1, range.from, {
    end_col = range.to,
    hl_group = "CsvActiveCell",
    priority = CELL_PRIORITY,
  })
end

--- Drop the record for `bufnr`, once the buffer is gone. nvim reuses buffer
--- numbers, so a record left behind would describe the next buffer.
---@param bufnr integer
function M.destroy(bufnr)
  for window, active in pairs(active_cells) do
    if active.bufnr == bufnr then
      active_cells[window] = nil
    end
  end
end

--- Whether the real cursor has left the byte the active cell parked it on,
--- which is what says the user moved it.
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

--- The cell drawn at `line` and byte `byte` of the buffer. A line holding a
--- border or the header answers with the nearest data line, so every position
--- in the buffer names a cell.
---@param buffer csv.Buffer
---@param line integer
---@param byte integer 0-based, as nvim reports a cursor.
---@return csv.Cell|nil
function M.cell_at(buffer, line, byte)
  local layout = buffer.layout
  if not layout or layout.first_line > layout.last_line then
    return nil
  end

  local buffer_line = math.min(math.max(line, layout.first_line), layout.last_line)
  local column_number = math.min(
    layout_module.column_number_at(layout, buffer_line, byte),
    layout_module.column_count(layout)
  )

  local row = layout_module.row_at_line(layout, buffer_line)
  local column = layout_module.column_at(layout, column_number)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

--- The cell the real cursor is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.cell(buffer, window)
  local position = vim.api.nvim_win_get_cursor(window)
  return M.cell_at(buffer, position[1], position[2])
end

--- The cell a move of the real cursor was aiming for.
---
--- A cursor that landed in another cell names that cell, which is what a click,
--- a search or `$` means. A cursor still inside the cell it started in was moved
--- by something too small to leave it, such as `l` in a cell drawn twenty wide,
--- and the cell one step that way is what was meant.
---
--- Sideways is the only direction that can be meant here, so a cursor that kept
--- its byte kept its cell. `k` on the first row of the page is that: the cursor
--- reaches the border line above and `cell_at` brings it back.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.moved_cell(buffer, window)
  local landed = M.cell(buffer, window)
  local active = get(buffer, window)
  if not landed or not active then
    return landed
  end

  local stayed = landed.row.row_id == active.row.row_id
    and landed.column.column_id == active.column.column_id
  local byte = vim.api.nvim_win_get_cursor(window)[2]
  if not stayed or byte == active.position[2] then
    return landed
  end

  local columns = byte > active.position[2] and 1 or -1
  return layout_module.step_cell(buffer.layout, landed, { rows = 0, columns = columns })
end

--- The cell that is active in `window`, which is where the plugin last put the
--- cursor.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.active(buffer, window)
  local active = get(buffer, window)
  return active and { row = active.row, column = active.column } or nil
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
  local column_number = layout_module.column_number(buffer.layout, cell.column)
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
  local cell = M.cell(buffer, window)
  if not cell then
    return nil
  end
  local delta = { rows = rows, columns = columns }
  return M.move_to(buffer, window, layout_module.step_cell(buffer.layout, cell, delta))
end

--- Put the active cell back in the column it was in before a render. The new
--- text has its own column widths, so the byte the cursor is on may now be in
--- another column, and the column is what says where the user was.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.restore(buffer, window)
  local cell = M.cell(buffer, window)
  local active = get(buffer, window)
  if cell and active and layout_module.column_number(buffer.layout, active.column) then
    cell.column = active.column
  end
  return M.move_to(buffer, window, cell)
end

--- The column the active cell is in, or nil before the first render.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Column|nil
function M.column(buffer, window)
  local cell = M.cell(buffer, window)
  return cell and cell.column or nil
end

--- Highlight one column of every row briefly. A redraw clears extmarks, so this
--- only holds while the text it describes is the text on screen.
---@param buffer csv.Buffer
---@param column csv.Column
function M.flash_column(buffer, column)
  if not buffer.layout then
    return
  end
  local column_number = layout_module.column_number(buffer.layout, column)
  if not column_number then
    return
  end

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
  local function flash(buffer_line)
    local from, to = layout_module.cell_bounds(buffer.layout, buffer_line, column_number)
    if from then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, flash_namespace, buffer_line - 1, from, {
        end_col = to,
        hl_group = "CsvFlash",
      })
    end
  end

  flash(buffer.layout.header_line)
  for buffer_line = buffer.layout.first_line, buffer.layout.last_line do
    flash(buffer_line)
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buffer.bufnr) then
      vim.api.nvim_buf_clear_namespace(buffer.bufnr, flash_namespace, 0, -1)
    end
  end, FLASH_MILLISECONDS)
end

--- `guicursor` with this plugin's entry taken out, which is the value it held
--- before a table hid the cursor. It splits on commas and drops the entry, so
--- the commas around it come out with it. nvim rejects an empty entry.
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
--- entry back out. The value is the whole record: taking the entry out rebuilds
--- what was there, which leaves another plugin's cursor styling as that plugin
--- set it.
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
--- Entering a buffer is what decides it, so a missed event lasts until the next
--- entry. `BufLeave` goes missing whenever a buffer is wiped while it is current
--- or a window opens with `noautocmd`, which telescope and snacks both do.
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
