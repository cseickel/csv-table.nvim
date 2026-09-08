--[[
Defines every highlight group the plugin uses.

Registers a decoration provider that draws extmarks for:
- the borders
- the header text
- date cells, and number cells colored by sign
]]

local buffer = require("csv-table.buffer")
local format = require("csv-table.format")
local layout = require("csv-table.layout")

local M = {}

local namespace = vim.api.nvim_create_namespace("csv-syntax")

-- Under the 4096 an extmark takes by default, so the marks and the selection
-- draw over the coloring.
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

--- The kind of every column that takes a color, keyed by column number. A number
--- gets its kind rather than a group, since the sign of the value picks which of
--- the two number groups it takes.
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
  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, from, {
    end_col = to,
    hl_group = group,
    priority = PRIORITY,
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

--- The layout and the column kinds for the window nvim is drawing. `on_win`
--- fills it once and every `on_line` for that window reads it.
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
  -- `on_win` already decided this window has a table, so `current_window` is
  -- set. The guard is here because nvim drops a provider that raises, which
  -- would end coloring for the session.
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

--- Define the groups and register the provider. One provider covers every
--- window, so `on_win` is what decides a window is showing a table.
---@param group integer
function M.setup(group)
  define_groups()
  -- A colorscheme runs `highlight clear` first, which takes every group above
  -- with it.
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_groups })
  vim.api.nvim_set_decoration_provider(namespace, { on_win = on_win, on_line = on_line })
end

return M
