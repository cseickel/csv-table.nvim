--[[
Reading `xan view` output.

`view` draws a bordered table, so the rendered text already says where every
column starts and which source row each line came from. This module turns that
text into the lookups the cursor and the highlighting need, and holds nothing
else.

The row id is drawn as the first cell because the drawn table is the only way it
reaches Lua. It answers no question the reader has, so `parse` reads it into
`rowids` and cuts that cell from every line. What the buffer receives starts at
the row number, and nothing on screen can be yanked or searched by row id.

Every column is drawn at the same display width on every line, so one set of
cell ranges describes the whole table in display columns. The cursor and the
extmarks take byte offsets, and a line holding a multi-byte character has its
separators at different byte offsets than the header, so `parse` keeps the
header's byte ranges once and a line's own byte ranges only where they differ.

A cell is bounded by the separators around it, or by the end of the line where
the theme in use draws no outer border.

It is pure Lua and can be exercised without nvim.
]]

local columns = require("csv-table.columns")

local M = {}

local SEPARATOR = "│"

--- The spaces `view` puts either side of every cell.
local CELL_PADDING = 2

---@class csv.CellRange
---@field from integer 0-based byte offset of the first byte in the cell.
---@field to integer   0-based byte offset just past the cell.

---@class csv.Layout
---@field lines string[]    Buffer lines, borders included.
---@field header integer    Index of the header line.
---@field first_row integer Index of the first data line, past `last_row` when empty.
---@field last_row integer  Index of the last data line.
---@field rowids table<integer, integer> Source row id, keyed by line index.
---@field lines_by_rowid table<integer, integer> Line index, keyed by source row id.
---@field ranges csv.CellRange[] The header's cells, which every line shares unless it is listed below.
---@field ranges_by_line table<integer, csv.CellRange[]> The cells of each line whose byte offsets differ from the header's.

---@param value string
---@return string
local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The byte range of every cell on one line. The ends of the line bound the
--- first and last cells, and a zero width range is dropped, so the count comes
--- out the same whether or not the theme in use draws the outer borders. `view`
--- pads every cell, so no real cell is empty.
---@param line string
---@return csv.CellRange[]
local function scan(line)
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

---@param left csv.CellRange[]
---@param right csv.CellRange[]
---@return boolean
local function same_ranges(left, right)
  if #left ~= #right then
    return false
  end
  for index, range in ipairs(left) do
    if range.from ~= right[index].from or range.to ~= right[index].to then
      return false
    end
  end
  return true
end

--- The byte range of every cell on line `index`, cell 1 being the row number. A
--- rule has no cells, so `index` is the header or a data line.
---@param layout csv.Layout
---@param index integer
---@return csv.CellRange[]
function M.cell_ranges(layout, index)
  return layout.ranges_by_line[index] or layout.ranges
end

--- The byte range cell `cell` occupies on line `index`, as 0-based offsets
--- suitable for an extmark.
---@param layout csv.Layout
---@param index integer
---@param cell integer
---@return integer|nil from
---@return integer|nil to
function M.cell_bounds(layout, index, cell)
  local range = M.cell_ranges(layout, index)[cell]
  if not range then
    return nil, nil
  end
  return range.from, range.to
end

--- How wide cell `cell` is drawn, in characters, without the padding `view`
--- puts around every value. Every line pads its cells to the same width, so
--- the header answers for all of them.
---@param layout csv.Layout
---@param cell integer
---@return integer|nil
function M.cell_width(layout, cell)
  local range = layout.ranges[cell]
  if not range then
    return nil
  end
  local header = layout.lines[layout.header]
  return columns.text_length(header:sub(range.from + 1, range.to)) - CELL_PADDING
end

--- Which cell of line `index` holds byte offset `column`, cell 1 being the row
--- number. A byte on a separator answers with the cell to its right, and a byte
--- past the last cell answers with the last cell, so every byte of the line
--- names a cell.
---@param layout csv.Layout
---@param index integer
---@param column integer 0-based byte offset, as nvim reports the cursor.
---@return integer
function M.cell_at(layout, index, column)
  local ranges = M.cell_ranges(layout, index)
  for cell, range in ipairs(ranges) do
    if column < range.to then
      return cell
    end
  end
  return #ranges
end

--- Whether `line` is one of the horizontal rules rather than a row. Every theme
--- draws its rules from dashes and corners, and only a header or a data row
--- holds the vertical separator.
---@param line string
---@return boolean
local function is_rule(line)
  return line:find("─", 1, true) ~= nil and line:find(SEPARATOR, 1, true) == nil
end

--- Where character `position` starts in `line`, counting from one. A character
--- begins at every byte that is not a UTF-8 continuation byte.
---@param line string
---@param position integer
---@return integer
local function byte_of_character(line, position)
  local characters = 0
  for index = 1, #line do
    local byte = line:byte(index)
    if byte < 0x80 or byte >= 0xC0 then
      characters = characters + 1
      if characters == position then
        return index
      end
    end
  end
  return #line + 1
end

--- `line` without its first cell: the `width` characters the cell is drawn in
--- and the separator that closes them, left where they sit behind `leading`.
---
--- Counting characters rather than bytes is what lets one cut serve a rule as
--- well as a row. Every line spends the same number of characters on the cell,
--- while a rule spends three bytes on each of them and a row of digits spends
--- one.
---@param line string
---@param border_width integer Characters of outer border ahead of the cell, 1 or 0.
---@param width integer Characters the cell is drawn in, padding included.
---@return string
local function without_first_cell(line, border_width, width)
  local from = byte_of_character(line, border_width + 1)
  local to = byte_of_character(line, border_width + width + 2)
  return line:sub(1, from - 1) .. line:sub(to)
end

--- Read the table `xan view` drew. It pads its output with a blank line at each
--- end, and draws a top rule, a header, a rule, the rows, and a bottom rule.
---
--- The row ids come out of the first cell before that cell is cut away, so
--- every range this returns describes the text the buffer will hold.
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

  local header_ranges = scan(lines[1])
  if #header_ranges < 2 then
    return nil, "xan view drew no row id"
  end
  -- The outer border is one character where the theme draws one, and `scan`
  -- starts the first cell past it.
  local border_width = header_ranges[1].from > 0 and 1 or 0
  local id_width = header_ranges[1].to - header_ranges[1].from

  local first_row, last_row = 3, #lines - 1
  local rowids = {}
  local lines_by_rowid = {}
  for index = first_row, last_row do
    local line = lines[index]
    local id = scan(line)[1]
    local rowid = id and tonumber(trim(line:sub(id.from + 1, id.to)))
    if rowid then
      rowids[index] = rowid
      lines_by_rowid[rowid] = index
    end
  end

  for index = 1, #lines do
    lines[index] = without_first_cell(lines[index], border_width, id_width)
  end

  local layout = {
    lines = lines,
    header = 1,
    first_row = first_row,
    last_row = last_row,
    rowids = rowids,
    lines_by_rowid = lines_by_rowid,
    ranges = scan(lines[1]),
    ranges_by_line = {},
  }

  for index = first_row, last_row do
    local ranges = scan(lines[index])
    if not same_ranges(ranges, layout.ranges) then
      layout.ranges_by_line[index] = ranges
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
