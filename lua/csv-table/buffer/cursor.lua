--[[
Tracks the cell the user is on, one per window, with the real cursor hidden and
parked at one edge of that cell.
]]

local color = require("csv-table.buffer.color")

local M = {}

local cell_namespace = vim.api.nvim_create_namespace("csv-active-cell")
local flash_namespace = vim.api.nvim_create_namespace("csv-flash")
local FLASH_MILLISECONDS = 250

-- The modes a table buffer is read in. The command line keeps its cursor, so `:`,
-- `/` and every `vim.ui.input` prompt can be typed into.
local HIDDEN_CURSOR = "n-v-o:CsvHiddenCursor"

--- Characters kept on screen past the active cell, which is what shows the cell's
--- border and a slice of the next column for orientation.
local PREVIEW = 8

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
  if not range then
    return
  end

  local edge = "left"
  local previous = get(buffer, window)
  if previous then
    local was = buffer.page:column_number(previous.column)
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
    column = buffer.page:column_at(column_number),
    edge = edge,
  }

  vim.api.nvim_buf_clear_namespace(buffer.bufnr, cell_namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer.bufnr, cell_namespace, row.buffer_line - 1, range.from, {
    end_col = range.to,
    hl_group = "CsvActiveCell",
    priority = color.CELL_PRIORITY,
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

--- The cell the real cursor is in.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.cell(buffer, window)
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
  return buffer.page:step_cell(landed, { rows = 0, columns = columns })
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
  local cell = M.cell(buffer, window)
  if not cell then
    return nil
  end
  return M.move_to(buffer, window, buffer.page:step_cell(cell, { rows = rows, columns = columns }))
end

--- Put the active cell back in the column it was in before a render. The new text
--- has its own column widths, so the byte the cursor is on may now be in another
--- column, and the column is what says where the user was.
---@param buffer csv.Buffer
---@param window integer
---@return csv.Cell|nil
function M.restore(buffer, window)
  local cell = M.cell(buffer, window)
  local active = get(buffer, window)
  if cell and active and buffer.page:column_number(active.column) then
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

--- `guicursor` with this plugin's entry taken out, which is the value it held
--- before a table hid the cursor. nvim rejects an empty entry.
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
---
--- `guicursor` is global and holds one entry per mode, the last entry for a mode
--- winning, so hiding is appending an entry and showing is taking it back out.
--- Rebuilding from the value leaves another plugin's cursor styling as that
--- plugin set it.
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
