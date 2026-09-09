--[[
Every color drawn into a table buffer: the groups, the order they stack in, and
the two ways they reach the screen.

- a decoration provider paints the borders, the header and the typed cells, which
  are decided by the text on the line and so are redrawn on every scroll
- extmarks paint the marked rows, the marked columns and the selection, which are
  decided by the query and so are redrawn when it changes

`csv-table.buffer.cursor` paints the active cell and the flash, since both follow
the cursor rather than the text, and it takes their priority from here.
]]

local format = require("csv-table.file.format")

local M = {}

local syntax_namespace = vim.api.nvim_create_namespace("csv-syntax")
local marks_namespace = vim.api.nvim_create_namespace("csv-marks")

-- The stack, bottom to top. An extmark takes 4096 by default, which is what the
-- marks and the flash sit on.
M.SYNTAX_PRIORITY = 100
M.SELECTION_PRIORITY = 4200
M.CELL_PRIORITY = 4300

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
  -- `blend = 100` is what hides the cursor drawn in this group.
  CsvHiddenCursor = { blend = 100 },
}

local function define_groups()
  for name, spec in pairs(GROUPS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("error", spec, { default = true }))
  end
end

-- Painted by the decoration provider ------------------------------------------

--- The kind of every column that takes a color, keyed by column number. A number
--- gets its kind rather than a group, since the sign of the value picks which of
--- the two number groups it takes.
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

--- The group a cell takes, or nil when the cell holds nothing. `view` pads every
--- cell, so the value starts at the first non-space.
---@param kind "number"|"date"
---@param text string The cell as it is drawn, padding included.
---@return string|nil
local function group_of(kind, text)
  local first = text:match("^%s*(%S)")
  if not first then
    return nil
  end
  if kind == "date" then
    return "CsvDate"
  end
  return first == "-" and "CsvNumberNegative" or "CsvNumberPositive"
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

--- Draw the gaps between the cells of one line, and the run at either end that
--- holds the outer border.
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
local current_window = nil

---@param bufnr integer
---@return boolean whether this window holds a table to color.
local function on_win(_, _, bufnr)
  -- Required here because `csv-table.buffer` requires this module to redraw.
  local buf = require("csv-table.buffer").get(bufnr)
  if not buf then
    current_window = nil
    return false
  end
  current_window = { page = buf.page, kinds = cell_kinds(buf) }
  return true
end

---@param bufnr integer
---@param row integer 0-based.
local function on_line(_, _, bufnr, row)
  -- `on_win` already decided this window has a table, so `current_window` is set.
  -- The guard is here because nvim drops a provider that raises, which would end
  -- coloring for the session.
  if not current_window then
    return
  end

  local page = current_window.page
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
      local kind = current_window.kinds[column_number]
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

--- Draw the selected cells. The selected columns are next to each other, so one
--- extmark per line spans the first column's left edge to the last one's right.
---@param buf csv.Buffer
local function draw_selection(buf)
  local bounds = buf.query:selection_bounds(buf.page)
  if not bounds then
    return
  end

  for line = bounds.top, bounds.bottom do
    local cells = buf.page:cell_ranges(line)
    local first, last = cells[bounds.left], cells[bounds.right]
    if first and last then
      vim.api.nvim_buf_set_extmark(buf.bufnr, marks_namespace, line - 1, first.from, {
        end_col = last.to,
        hl_group = "CsvSelection",
        priority = M.SELECTION_PRIORITY,
      })
    end
  end
end

--- Draw the marks and the selection again, which is what a change to either or
--- to the page below them costs.
---@param buf csv.Buffer
function M.redraw(buf)
  vim.api.nvim_buf_clear_namespace(buf.bufnr, marks_namespace, 0, -1)
  draw_marks(buf)
  draw_selection(buf)
end

--- Define the groups and register the provider. One provider covers every window,
--- so `on_win` is what decides a window is showing a table.
---@param group integer
function M.setup(group)
  define_groups()
  -- A colorscheme runs `highlight clear` first, which takes every group above
  -- with it.
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_groups })
  vim.api.nvim_set_decoration_provider(syntax_namespace, { on_win = on_win, on_line = on_line })
end

return M
