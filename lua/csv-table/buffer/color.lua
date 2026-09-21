--[[
Every color drawn into a table buffer, and the two ways it gets there.

A decoration provider paints the borders, the header and the typed cells. The
line text decides those, so they are redrawn on every scroll. Extmarks paint the
marked rows and columns. The query decides those, so they are redrawn when it
changes.

`csv-table.view` paints the active cell and the selection, which belong to one
window rather than to the buffer.
]]

local format = require("csv-table.file.format")

local M = {}

local syntax_namespace = vim.api.nvim_create_namespace("csv-syntax")
local marks_namespace = vim.api.nvim_create_namespace("csv-marks")
local flash_namespace = vim.api.nvim_create_namespace("csv-flash")

local FLASH_MILLISECONDS = 250

-- The bottom of the stack. An extmark defaults to 4096, so the marks and the flash
-- paint over this, and `csv-table.view` paints over those.
M.SYNTAX_PRIORITY = 100

local GROUPS = {
  CsvBorder = { fg = "#444444" },
  CsvRowNumber = { link = "CsvBorder" },
  CsvHeader = { fg = "#ededed", bold = true },
  CsvNumberPositive = { fg = "#85e0b1" },
  CsvNumberNegative = { fg = "#ff8066" },
  CsvDate = { fg = "#ffd685" },
  CsvMarkedRow = { link = "DiffAdd" },
  CsvMarkedColumn = { link = "DiffText" },
  CsvSelection = { link = "Visual" },
  CsvActiveCell = { reverse = true },
  CsvFlash = { link = "IncSearch" },
  -- `blend = 100` hides a cursor drawn in this group.
  CsvHiddenCursor = { blend = 100 },
}

--- Define every group as a default, which a colorscheme's own definition wins over.
function M.define_groups()
  for name, spec in pairs(GROUPS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("error", spec, { default = true }))
  end
end

-- Painted by the decoration provider ------------------------------------------

--- The kind of every column that takes a color, keyed by column number. The kind
--- rather than the group, because the sign of each value picks which of the two
--- number groups it takes.
---@param buf csv.Buffer
---@return table<integer, "number"|"date">
local function cell_kinds(buf)
  local kinds = {}
  for column_number, column in ipairs(buf.page.columns) do
    local column_format = buf.query.file.formats[column.column_id]
    if format.is_numeric(column_format) then
      kinds[column_number] = "number"
    elseif column_format and column_format.kind == "date" then
      kinds[column_number] = "date"
    end
  end
  return kinds
end

--- The group a cell takes, or nil when the cell holds nothing. `xan view` pads
--- every cell, so the value starts at the first non-space.
---@param kind "number"|"date"
---@param text string The cell as it is drawn, padding included.
---@return string|nil
local function group_of(kind, text)
  local first_character = text:match("^%s*(%S)")
  if not first_character then
    return nil
  end
  if kind == "date" then
    return "CsvDate"
  end
  return first_character == "-" and "CsvNumberNegative" or "CsvNumberPositive"
end

---@param bufnr integer
---@param row integer 0-based, as nvim numbers the lines it draws.
---@param from integer
---@param to integer
---@param group string
local function draw(bufnr, row, from, to, group)
  vim.api.nvim_buf_set_extmark(bufnr, syntax_namespace, row, from, {
    end_col = to,
    hl_group = group,
    priority = M.SYNTAX_PRIORITY,
    ephemeral = true,
  })
end

--- Draw the gaps between the cells of one line and the outer border at each end.
---@param bufnr integer
---@param row integer
---@param line string
---@param ranges csv.CellRange[]
local function draw_borders(bufnr, row, line, ranges)
  local from = 0
  for _, range in ipairs(ranges) do
    if range.from > from then
      draw(bufnr, row, from, range.from, "CsvBorder")
    end
    from = range.to
  end
  if #line > from then
    draw(bufnr, row, from, #line, "CsvBorder")
  end
end

--- The page and the column kinds for the window nvim is drawing. `on_win` fills
--- it once and every `on_line` for that window reads it.
---@type { page: csv.Page, kinds: table<integer, "number"|"date"> }|nil
local drawing_state = nil

---@param bufnr integer
---@return boolean whether this window holds a table to color.
local function on_win(_, _, bufnr)
  -- Required here because `csv-table.buffer` requires this module.
  local buf = require("csv-table.buffer").get(bufnr)
  if not buf then
    drawing_state = nil
    return false
  end
  drawing_state = { page = buf.page, kinds = cell_kinds(buf) }
  return true
end

---@param bufnr integer
---@param row integer 0-based.
local function on_line(_, _, bufnr, row)
  -- `on_win` set this for any window nvim gets here for. The guard stays because
  -- nvim drops a provider that raises, which would end coloring for the session.
  if not drawing_state then
    return
  end

  local page = drawing_state.page
  local index = row + 1
  local line = page.lines[index]
  if not line then
    return
  end

  -- A border line is border all the way across.
  local header = index == page.header_line
  if not header and (index < page.first_line or index > page.last_line) then
    return draw(bufnr, row, 0, #line, "CsvBorder")
  end

  local ranges = page:cell_ranges(index)
  draw_borders(bufnr, row, line, ranges)

  for column_number, range in ipairs(ranges) do
    local group
    if header then
      group = "CsvHeader"
    else
      local kind = drawing_state.kinds[column_number]
      group = kind and group_of(kind, line:sub(range.from + 1, range.to))
    end
    if group then
      draw(bufnr, row, range.from, range.to, group)
    end
  end
end

-- Painted from the query ------------------------------------------------------

---@param buf csv.Buffer
local function draw_marks(buf)
  local page = buf.page
  for buffer_line = page.first_line, page.last_line do
    local row = page:row_at_line(buffer_line)
    if row and buf.query.marked[row.row_id] then
      vim.api.nvim_buf_set_extmark(buf.bufnr, marks_namespace, buffer_line - 1, 0, {
        line_hl_group = "CsvMarkedRow",
      })
    end
  end

  for column_number, column in ipairs(page.columns) do
    if buf.query.marked_columns[column.column_id] then
      local from, to = page:cell_bounds(page.header_line, column_number)
      if from then
        vim.api.nvim_buf_set_extmark(buf.bufnr, marks_namespace, page.header_line - 1, from, {
          end_col = to,
          hl_group = "CsvMarkedColumn",
        })
      end
    end
  end
end

--- Remove every extmark this module drew on `bufnr`. The provider's marks are
--- ephemeral, so they stop on their own once the buffer is no longer a table.
---@param bufnr integer
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, marks_namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, flash_namespace, 0, -1)
end

--- Draw the marks again, after the marks or the page under them changed. A flash
--- still running named cells of the page being replaced, so it goes too.
---@param buf csv.Buffer
function M.redraw(buf)
  vim.api.nvim_buf_clear_namespace(buf.bufnr, marks_namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf.bufnr, flash_namespace, 0, -1)
  draw_marks(buf)
end

--- Highlight one column on every row for `FLASH_MILLISECONDS`, or until a redraw
--- replaces the page the flashed cells belong to.
---@param buf csv.Buffer
---@param column csv.Column
function M.flash_column(buf, column)
  local column_number = buf.page:column_number(column)
  if not column_number then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf.bufnr, flash_namespace, 0, -1)
  local function flash(buffer_line)
    local from, to = buf.page:cell_bounds(buffer_line, column_number)
    if from then
      vim.api.nvim_buf_set_extmark(buf.bufnr, flash_namespace, buffer_line - 1, from, {
        end_col = to,
        hl_group = "CsvFlash",
      })
    end
  end

  flash(buf.page.header_line)
  for buffer_line = buf.page.first_line, buf.page.last_line do
    flash(buffer_line)
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      vim.api.nvim_buf_clear_namespace(buf.bufnr, flash_namespace, 0, -1)
    end
  end, FLASH_MILLISECONDS)
end

--- Define the groups and register the provider. One provider covers every window,
--- and `on_win` decides whether the window shows a table.
function M.setup()
  M.define_groups()
  vim.api.nvim_set_decoration_provider(syntax_namespace, { on_win = on_win, on_line = on_line })
end

return M
