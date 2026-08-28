--[[
Reading `xan view` output.

`view` draws a bordered table, so the rendered text already says where every
column starts and which source row each line came from. This module turns that
text into the lookups the cursor needs, and holds nothing else.

Every lookup works from the separators on the line it is given. `view` pads
cells to display width rather than byte length, so a line holding a multi-byte
character has its separators at different byte offsets than the header, and
offsets taken from one line never describe another.

A cell is bounded by the separators around it, or by the end of the line where
the theme in use draws no outer border.

It is pure Lua and can be exercised without nvim.
]]

local columns = require("csv-table.columns")

local M = {}

local SEPARATOR = "│"

--- The spaces `view` puts either side of every cell.
local CELL_PADDING = 2

---@class csv.Layout
---@field lines string[]    Buffer lines, borders included.
---@field header integer    Index of the header line.
---@field first_row integer Index of the first data line, past `last_row` when empty.
---@field last_row integer  Index of the last data line.
---@field rowids table<integer, integer> Source row id, keyed by line index.
---@field lines_by_rowid table<integer, integer> Line index, keyed by source row id.

---@param value string
---@return string
local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@class csv.CellRange
---@field from integer 0-based byte offset of the first byte in the cell.
---@field to integer   0-based byte offset just past the cell.

--- The byte range of every cell on one line, cell 1 being the row id. The ends
--- of the line bound the first and last cells, and a zero width range is
--- dropped, so the count comes out the same whether or not the theme in use
--- draws the outer borders. `view` pads every cell, so no real cell is empty.
---@param line string
---@return csv.CellRange[]
function M.cell_ranges(line)
  local ranges = {}
  local from = 0
  local search = 1
  while true do
    local found = line:find(SEPARATOR, search, true)
    if not found then
      break
    end
    if found - 1 > from then
      table.insert(ranges, { from = from, to = found - 1 })
    end
    from = found - 1 + #SEPARATOR
    search = found + #SEPARATOR
  end

  if #line > from then
    table.insert(ranges, { from = from, to = #line })
  end
  return ranges
end

--- The byte range cell `index` occupies on `line`, as 0-based offsets suitable
--- for an extmark.
---@param line string
---@param index integer
---@return integer|nil from
---@return integer|nil to
function M.cell_bounds(line, index)
  local range = M.cell_ranges(line)[index]
  if not range then
    return nil, nil
  end
  return range.from, range.to
end

--- How wide cell `index` is drawn, in characters, without the padding `view`
--- puts around every value. Every line pads its cells to the same width, so any
--- line of the table answers this.
---@param line string
---@param index integer
---@return integer|nil
function M.cell_width(line, index)
  local from, to = M.cell_bounds(line, index)
  if not from then
    return nil
  end
  return columns.text_length(line:sub(from + 1, to)) - CELL_PADDING
end

--- The trimmed text of every cell on one line, cell 1 being the row id.
---@param line string
---@return string[]
function M.cells(line)
  local cells = {}
  for index, range in ipairs(M.cell_ranges(line)) do
    cells[index] = trim(line:sub(range.from + 1, range.to))
  end
  return cells
end

--- Which cell of `line` holds byte offset `column`, cell 1 being the row id.
---@param line string
---@param column integer 0-based byte offset, as nvim reports the cursor.
---@return integer|nil
function M.cell_at(line, column)
  for index, range in ipairs(M.cell_ranges(line)) do
    if column >= range.from and column < range.to then
      return index
    end
  end
  return nil
end

--- Whether `line` is one of the horizontal rules rather than a row. Every theme
--- draws its rules from dashes and corners, and only a header or a data row
--- carries the vertical separator.
---@param line string
---@return boolean
local function is_rule(line)
  return line:find("─", 1, true) ~= nil and line:find(SEPARATOR, 1, true) == nil
end

--- Read the table `xan view` drew. It pads its output with a blank line at each
--- end, and draws a top rule, a header, a rule, the rows, and a bottom rule.
---@param output string[]
---@return csv.Layout|nil layout
---@return string|nil error
function M.parse(output)
  local lines = {}
  for _, line in ipairs(output) do
    if trim(line) ~= "" then
      table.insert(lines, line)
    end
  end

  if #lines < 4 or not is_rule(lines[1]) or not is_rule(lines[3]) then
    return nil, "xan view did not produce a table"
  end
  -- Cut the top rule
  table.remove(lines, 1)

  local layout = {
    lines = lines,
    header = 1,
    first_row = 3,
    last_row = #lines - 1,
    rowids = {},
    lines_by_rowid = {},
  }

  for index = layout.first_row, layout.last_row do
    local rowid = tonumber(M.cells(lines[index])[1])
    if rowid then
      layout.rowids[index] = rowid
      layout.lines_by_rowid[rowid] = index
    end
  end

  return layout, nil
end

--- How many rows the table holds.
---@param layout csv.Layout
---@return integer
function M.row_count(layout)
  return layout.last_row - layout.first_row + 1
end

return M
