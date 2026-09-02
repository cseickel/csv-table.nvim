--[[
Colour.

Every group this plugin paints with is defined here, and the table's own colours
are painted here too. A colour follows from where a cell is and what its column
holds, both of which `csv-table.layout` and `csv-table.format` already know, so
nothing here searches the text.

The decoration provider runs only for the lines nvim is drawing, and its marks
are ephemeral, so nothing is stored between redraws and a render that replaces
every line has nothing to reapply.

A cell holding text is left unpainted so it reads in the normal foreground, so
the border is painted as the gaps between the cells rather than as a layer under
them. Every group painted here sets a foreground alone, which leaves the
background to the row marks and the selection.
]]

local buffer = require("csv-table.buffer")
local format = require("csv-table.format")
local layout = require("csv-table.layout")
local selection = require("csv-table.selection")

local M = {}

local namespace = vim.api.nvim_create_namespace("csv-syntax")

-- Under the 4096 an extmark takes by default, so the marks and the selection
-- both paint over the colouring rather than under it. Nothing painted here
-- overlaps anything else painted here, so one priority covers all of it.
local PRIORITY = 100

local GROUPS = {
  CsvBorder = { fg = "#444444" },
  CsvRowId = { link = "CsvBorder" },
  CsvHeader = { fg = "#ededed", bold = true },
  CsvNumberPositive = { fg = "#85e0b1" },
  CsvNumberNegative = { fg = "#ff8066" },
  CsvDate = { fg = "#ffd685" },
  CsvMarkedRow = { link = "DiffAdd" },
  CsvMarkedColumn = { link = "DiffText" },
  CsvSelection = { link = "Visual" },
  CsvCursorCell = { reverse = true },
  CsvFlash = { link = "IncSearch" },
  -- `blend = 100` is what hides the cursor drawn in this group.
  CsvHiddenCursor = { blend = 100 },
}

local function define_groups()
  for name, spec in pairs(GROUPS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("error", spec, { default = true }))
  end
end

--- What each cell of a data row is coloured by, keyed by cell number. Cell 1 is
--- the row id, so the column shown at position `n` is cell `n + 1`. A number
--- carries its kind rather than a group, because the sign of the value decides
--- which of the two number groups it takes.
---@param state csv.State
---@return table<integer, "number"|"date">
local function cell_kinds(state)
  local kinds = {}
  for position, column in ipairs(selection.selected(state)) do
    local column_format = state.formats[column.index]
    if format.is_numeric(column_format) then
      kinds[position + 1] = "number"
    elseif column_format and column_format.kind == "date" then
      kinds[position + 1] = "date"
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
local function paint(bufnr, row, from, to, group)
  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, from, {
    end_col = to,
    hl_group = group,
    priority = PRIORITY,
    ephemeral = true,
  })
end

--- Paint the separators of one line: the gap between each pair of cells, and
--- the run at either end where the theme in use draws an outer border.
---@param bufnr integer
---@param row integer
---@param line string
---@param ranges csv.CellRange[]
local function paint_borders(bufnr, row, line, ranges)
  local from = 0
  for _, range in ipairs(ranges) do
    if range.from > from then
      paint(bufnr, row, from, range.from, "CsvBorder")
    end
    from = range.to
  end
  if #line > from then
    paint(bufnr, row, from, #line, "CsvBorder")
  end
end

--- The layout and the cell kinds for the window being drawn, read once per
--- window rather than once per line.
---@type { layout: csv.Layout, kinds: table<integer, "number"|"date"> }|nil
local drawing = nil

---@param bufnr integer
---@return boolean whether this window holds a table to colour.
local function on_win(_, _, bufnr)
  local buf = buffer.get(bufnr)
  if not buf or not buf.layout then
    drawing = nil
    return false
  end
  drawing = { layout = buf.layout, kinds = cell_kinds(buf.state) }
  return true
end

---@param bufnr integer
---@param row integer 0-based.
local function on_line(_, _, bufnr, row)
  -- `on_win` decided this window has a table to colour, so `drawing` is set.
  -- Reading it unguarded would end every buffer's colouring for the session,
  -- because nvim drops a provider that raises.
  if not drawing then
    return
  end

  local painted = drawing.layout
  local index = row + 1
  local line = painted.lines[index]
  if not line then
    return
  end

  -- A horizontal rule holds nothing but border.
  local header = index == painted.header
  if not header and (index < painted.first_row or index > painted.last_row) then
    return paint(bufnr, row, 0, #line, "CsvBorder")
  end

  local ranges = layout.cell_ranges(painted, index)
  paint_borders(bufnr, row, line, ranges)

  for cell, range in ipairs(ranges) do
    local group
    if header then
      group = "CsvHeader"
    elseif cell == 1 then
      group = "CsvRowId"
    else
      local kind = drawing.kinds[cell]
      group = kind and group_of(kind, line:sub(range.from + 1, range.to))
    end
    if group then
      paint(bufnr, row, range.from, range.to, group)
    end
  end
end

--- Define the groups and start colouring. One provider covers every window, so
--- `on_win` is what decides a window is showing a table.
function M.setup()
  define_groups()
  -- A colorscheme runs `highlight clear` before it defines anything, which
  -- takes every group above with it.
  vim.api.nvim_create_autocmd("ColorScheme", { callback = define_groups })
  vim.api.nvim_set_decoration_provider(namespace, { on_win = on_win, on_line = on_line })
end

return M
