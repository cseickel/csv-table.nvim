--[[
Defines `csv.Layout`, one page of the table as it is drawn.
`csv-table.reader.parse` builds it, and everything here reads it.

- lookups from a row id, a row number, a line or a column to what draws it
- the byte range of every cell, which the cursor and the extmarks take
- `step_cell`, the cell a move lands on

Pure Lua, so it runs without nvim.
]]

local columns = require("csv-table.columns")

local M = {}

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
