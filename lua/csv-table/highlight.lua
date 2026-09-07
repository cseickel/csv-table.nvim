--[[
Color.

Every group this plugin draws with is defined here, and the table's own colors
are drawn here too. A color follows from where a cell is and what its column
holds, both of which `csv-table.layout` and `csv-table.format` already know, so
nothing here searches the text.

The decoration provider runs for the lines nvim is drawing, and its marks last
for that draw, so a render that replaces every line is answered by the next
draw asking again.

A cell holding text reads in the normal foreground, and the border is the gaps
between the cells. Every group here sets a foreground alone, which leaves the
background to the row marks and the selection.
]]

local buffer = require("csv-table.buffer")
local format = require("csv-table.format")
local layout = require("csv-table.layout")

local M = {}

local namespace = vim.api.nvim_create_namespace("csv-syntax")

-- Under the 4096 an extmark takes by default, so the marks and the selection
-- both draw over the coloring. One value covers every group here, which each
-- claim their own stretch of the line.
local PRIORITY = 100

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

--- What each cell of a data row is colored by, keyed by column number. A number
--- is keyed by its kind rather than by a group, because the sign of the value
--- decides which of the two number groups it takes.
---@param buf csv.Buffer
---@return table<integer, "number"|"date">
local function cell_kinds(buf)
  local kinds = {}
  for column_number, column in ipairs(buf.layout.columns) do
    local column_format = buf.state.formats[column.column_id]
    if format.is_numeric(column_format) then
      kinds[column_number] = "number"
    elseif column_format and column_format.kind == "date" then
      kinds[column_number] = "date"
    end
  end
  return kinds
end

--- The group a cell takes, or nil when the cell holds nothing. `view` pads every
--- cell, so the value is whatever follows the padding.
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
  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, from, {
    end_col = to,
    hl_group = group,
    priority = PRIORITY,
    ephemeral = true,
  })
end

--- Draw the separators of one line: the gap between each pair of cells, and the
--- run at either end where the theme in use draws an outer border.
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

--- The layout and the cell kinds for the window nvim is drawing. `on_win` fills
--- this once, and every `on_line` for that window reads it.
---@type { layout: csv.Layout, kinds: table<integer, "number"|"date"> }|nil
local current_window = nil

---@param bufnr integer
---@return boolean whether this window holds a table to color.
local function on_win(_, _, bufnr)
  local buf = buffer.get(bufnr)
  if not buf or not buf.layout then
    current_window = nil
    return false
  end
  current_window = { layout = buf.layout, kinds = cell_kinds(buf) }
  return true
end

---@param bufnr integer
---@param row integer 0-based.
local function on_line(_, _, bufnr, row)
  -- `on_win` decided this window has a table to color, so `current_window` is
  -- set. Reading it unguarded would end every buffer's coloring for the session,
  -- because nvim drops a provider that raises.
  if not current_window then
    return
  end

  local index = row + 1
  local line = current_window.layout.lines[index]
  if not line then
    return
  end

  -- A border line is border all the way across.
  local header = index == current_window.layout.header_line
  if not header and (index < current_window.layout.first_line or index > current_window.layout.last_line) then
    return draw(bufnr, row, 0, #line, "CsvBorder")
  end

  local ranges = layout.cell_ranges(current_window.layout, index)
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

--- Define the groups and start coloring. One provider covers every window, so
--- `on_win` is what decides a window is showing a table.
---@param group integer
function M.setup(group)
  define_groups()
  -- A colorscheme runs `highlight clear` before it defines anything, which
  -- takes every group above with it.
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_groups })
  vim.api.nvim_set_decoration_provider(namespace, { on_win = on_win, on_line = on_line })
end

return M
