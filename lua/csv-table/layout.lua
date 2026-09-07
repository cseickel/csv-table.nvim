--[[
Reading `xan view` output.

`view` draws a bordered table, so the rendered text already says where every
column starts and which source row each line came from. This module turns that
text into the lookups the active cell and the highlighting read.

The row id is drawn as the first cell because the drawn table is the only way it
reaches Lua. `parse` reads it into the row objects and cuts that cell from every
line, so the buffer starts at the first column the user chose, and what they
yank or search is what they read.

A row on the page is a `csv.Row`, built here and filed under each of the three
numbers that name it. A column on display is a `csv.Column`, and
`column_number_by_id` gives the position it is drawn at. Every parse builds both
afresh, so both describe the text on screen.

`view` draws three border lines: the top of the table, the one under the header,
and the bottom. The rest of the lines hold cells.

Every column is drawn at the same display width on every line, so one set of
cell ranges describes the whole table in display columns. The cursor and the
extmarks take byte offsets, and a line holding a multi-byte character has its
separators at different byte offsets than the header, so `parse` keeps the
header's byte ranges once and a line's own byte ranges only where they differ.

A cell runs between the separators around it. Under a theme that draws the outer
border, the first and last cells run to the ends of the line.

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

---@class csv.Cell
---@field row csv.Row
---@field column csv.Column

---@class csv.Row
---@field row_id integer      Source position, which survives filtering and sorting.
---@field row_number integer  What the row is numbered on screen.
---@field buffer_line integer Which line of the buffer draws it, borders counted.

---@class csv.Layout
---@field lines string[]      Buffer lines, borders included.
---@field header_line integer Line the header is drawn on.
---@field first_line integer  First data line, past `last_line` when the page is empty.
---@field last_line integer   Last data line.
---@field rows_by_number table<integer, csv.Row>
---@field rows_by_id table<integer, csv.Row>
---@field rows_by_line table<integer, csv.Row>
---@field columns csv.Column[] The columns on display, in display order. A column's position here is its `column_number`.
---@field column_number_by_id table<integer, integer>
---@field ranges csv.CellRange[] The header's cells, which every line shares unless it is listed below.
---@field ranges_by_line table<integer, csv.CellRange[]> The cells of each line whose byte offsets differ from the header's.

---@param value string
---@return string
local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The byte range of every cell on one line. The ends of the line bound the
--- first and last cells, and a zero width range is dropped, so a theme that
--- draws the outer border and one that leaves it off give the same count.
--- `view` pads every cell, so every real cell has width.
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

--- The byte range of every cell on `buffer_line`, indexed by column number.
--- `buffer_line` is the header or a data line, since those are the lines that
--- hold cells.
---@param layout csv.Layout
---@param buffer_line integer
---@return csv.CellRange[]
function M.cell_ranges(layout, buffer_line)
  return layout.ranges_by_line[buffer_line] or layout.ranges
end

--- The byte range column `column_number` occupies on `buffer_line`, as 0-based
--- offsets suitable for an extmark.
---@param layout csv.Layout
---@param buffer_line integer
---@param column_number integer
---@return integer|nil from
---@return integer|nil to
function M.cell_bounds(layout, buffer_line, column_number)
  local range = M.cell_ranges(layout, buffer_line)[column_number]
  if not range then
    return nil, nil
  end
  return range.from, range.to
end

--- How wide column `column_number` is drawn, in characters, once the padding
--- `view` puts around every value is taken back off. Every line pads its cells
--- to the same width, so the header answers for all of them.
---@param layout csv.Layout
---@param column_number integer
---@return integer|nil
function M.cell_width(layout, column_number)
  local range = layout.ranges[column_number]
  if not range then
    return nil
  end
  local header = layout.lines[layout.header_line]
  return columns.text_length(header:sub(range.from + 1, range.to)) - CELL_PADDING
end

--- Which column of `buffer_line` holds byte offset `byte`. A byte on a separator
--- answers with the column to its right, and a byte past the last cell answers
--- with the last column, so every byte of the line names a column.
---@param layout csv.Layout
---@param buffer_line integer
---@param byte integer 0-based, as nvim reports the cursor.
---@return integer column_number
function M.column_number_at(layout, buffer_line, byte)
  local ranges = M.cell_ranges(layout, buffer_line)
  for column_number, range in ipairs(ranges) do
    if byte < range.to then
      return column_number
    end
  end
  return #ranges
end

--- The row drawn on `buffer_line`, present for the data lines.
---@param layout csv.Layout
---@param buffer_line integer
---@return csv.Row|nil
function M.row_at_line(layout, buffer_line)
  return layout.rows_by_line[buffer_line]
end

--- The row `row_id` names, present while that row is on the page.
---@param layout csv.Layout
---@param row_id integer
---@return csv.Row|nil
function M.row_by_id(layout, row_id)
  return layout.rows_by_id[row_id]
end

--- The row drawn under `row_number`, present while that row is on the page.
---@param layout csv.Layout
---@param row_number integer
---@return csv.Row|nil
function M.row_by_number(layout, row_number)
  return layout.rows_by_number[row_number]
end

--- The column drawn at `column_number`.
---@param layout csv.Layout
---@param column_number integer
---@return csv.Column|nil
function M.column_at(layout, column_number)
  return layout.columns[column_number]
end

--- Where `column` is drawn, present while it is on display.
---@param layout csv.Layout
---@param column csv.Column
---@return integer|nil column_number
function M.column_number(layout, column)
  return layout.column_number_by_id[column.column_id]
end

--- How many columns are drawn.
---@param layout csv.Layout
---@return integer
function M.column_count(layout)
  return #layout.columns
end

--- Whether `line` is one of the three horizontal borders. Every theme draws
--- them from dashes and corners, and the header and the data rows are the lines
--- that hold a vertical separator.
---@param line string
---@return boolean
local function is_border_line(line)
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
--- Counting characters is what lets one cut serve a border line as well as a
--- row. Every line spends the same number of characters on the cell, while a
--- border line spends three bytes on each of them and a row of digits spends
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
--- end, and draws a top border, the header, a border, the rows, and a bottom
--- border. The blank lines go and the rest reaches the buffer, so the table
--- keeps its frame.
---
--- The row ids come out of the first cell before that cell is cut away, so
--- every range this returns describes the text the buffer will hold.
---@param output string[]
---@param display_columns csv.Column[] The columns drawn, in display order.
---@param first_row_number integer The number the first row of the page is drawn with.
---@return csv.Layout|nil layout
---@return string|nil error
function M.parse(output, display_columns, first_row_number)
  local lines = {}
  for _, line in ipairs(output) do
    if trim(line) ~= "" then
      table.insert(lines, line)
    end
  end

  if #lines < 4 or not is_border_line(lines[1]) or not is_border_line(lines[3]) then
    return nil, "xan view did not produce a table"
  end

  local header_line = 2
  local header_ranges = scan(lines[header_line])
  if #header_ranges < 2 then
    return nil, "xan view drew no row id"
  end
  -- The outer border is one character where the theme draws one, and `scan`
  -- starts the first cell past it.
  local border_width = header_ranges[1].from > 0 and 1 or 0
  local id_width = header_ranges[1].to - header_ranges[1].from

  local first_line, last_line = 4, #lines - 1
  local rows_by_number, rows_by_id, rows_by_line = {}, {}, {}
  for buffer_line = first_line, last_line do
    local line = lines[buffer_line]
    local cell = scan(line)[1]
    local row_id = cell and tonumber(trim(line:sub(cell.from + 1, cell.to)))
    if row_id then
      local row = {
        row_id = row_id,
        row_number = first_row_number + buffer_line - first_line,
        buffer_line = buffer_line,
      }
      rows_by_number[row.row_number] = row
      rows_by_id[row_id] = row
      rows_by_line[buffer_line] = row
    end
  end

  for index = 1, #lines do
    lines[index] = without_first_cell(lines[index], border_width, id_width)
  end

  local column_number_by_id = {}
  for column_number, column in ipairs(display_columns) do
    column_number_by_id[column.column_id] = column_number
  end

  local layout = {
    lines = lines,
    header_line = header_line,
    first_line = first_line,
    last_line = last_line,
    rows_by_number = rows_by_number,
    rows_by_id = rows_by_id,
    rows_by_line = rows_by_line,
    columns = display_columns,
    column_number_by_id = column_number_by_id,
    ranges = scan(lines[header_line]),
    ranges_by_line = {},
  }

  for buffer_line = first_line, last_line do
    local ranges = scan(lines[buffer_line])
    if not same_ranges(ranges, layout.ranges) then
      layout.ranges_by_line[buffer_line] = ranges
    end
  end

  return layout, nil
end

--- How many rows the table holds.
---@param layout csv.Layout
---@return integer
function M.row_count(layout)
  return layout.last_line - layout.first_line + 1
end

--- Where `cell` lands when it is taken `rows` down and `columns` across, kept
--- inside the table.
---@param layout csv.Layout
---@param cell csv.Cell
---@param delta { rows: integer, columns: integer }
---@return csv.Cell|nil
function M.step_cell(layout, cell, delta)
  local column_number = M.column_number(layout, cell.column)
  if not column_number then
    return nil
  end

  local line = math.min(
    math.max(cell.row.buffer_line + delta.rows, layout.first_line),
    layout.last_line
  )
  local number = math.min(math.max(column_number + delta.columns, 1), M.column_count(layout))

  local row = M.row_at_line(layout, line)
  local column = M.column_at(layout, number)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

return M
