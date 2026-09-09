--[[
Defines `csv.Page`, one page of the table as it is drawn: the buffer lines, the
byte range of every cell, and the lookups from a row id, a row number, a line or
a column to what draws it.

`csv-table.reader.parse` builds one out of what xan printed. `empty` is a page
nothing has been drawn on, and it answers every lookup with nothing rather than
with an error.

Pure Lua, so it runs without nvim.
]]

local text = require("csv-table.utils.text")

local M = {}

--- The spaces `xan view` puts either side of every cell.
local CELL_PADDING = 2

---@class csv.CellRange
---@field from integer 0-based byte offset of the first byte in the cell.
---@field to integer   0-based byte offset just past the cell.

---@class csv.Cell
---@field row csv.Row
---@field column csv.Column

---@class csv.CellRef
---@field row_id integer
---@field column_id integer

---@class csv.Row
---@field row_id integer      Source position, which survives filtering and sorting.
---@field row_number integer  What the row is numbered on screen.
---@field buffer_line integer Which line of the buffer draws it, borders counted.

---@class csv.Page
---@field lines string[]      Buffer lines, borders included.
---@field header_line integer Line the header is drawn on.
---@field first_line integer  First data line, past `last_line` when the page is empty.
---@field last_line integer   Last data line.
---@field rows_by_number table<integer, csv.Row>
---@field rows_by_id table<integer, csv.Row>
---@field rows_by_line table<integer, csv.Row>
---@field columns csv.Column[] The columns on display, in display order.
---@field column_number_by_id table<integer, integer>
---@field ranges csv.CellRange[] The header's cells, which every line shares unless it is listed below.
---@field ranges_by_line table<integer, csv.CellRange[]> The cells of each line whose byte offsets differ from the header's.
---@field file_version string What the file looked like when this page was read.
local Page = {}
Page.__index = Page

---@param fields table
---@return csv.Page
function M.new(fields)
  return setmetatable(fields, Page)
end

--- What names `cell` across a render, since a row id and a column id outlive the
--- page they were read from. `Page:cell_of` is the way back.
---@param cell csv.Cell
---@return csv.CellRef
function M.ref_of(cell)
  return { row_id = cell.row.row_id, column_id = cell.column.column_id }
end

--- A page nothing has been drawn on. `first_line` past `last_line` is what says
--- it holds no rows, which is the same answer a filter leaving nothing gives.
---@return csv.Page
function M.empty()
  return M.new({
    lines = {},
    header_line = 0,
    first_line = 1,
    last_line = 0,
    rows_by_number = {},
    rows_by_id = {},
    rows_by_line = {},
    columns = {},
    column_number_by_id = {},
    ranges = {},
    ranges_by_line = {},
    file_version = "",
  })
end

--- The byte range of every cell on `buffer_line`, indexed by column number.
---@param buffer_line integer
---@return csv.CellRange[]
function Page:cell_ranges(buffer_line)
  return self.ranges_by_line[buffer_line] or self.ranges
end

--- The byte range column `column_number` occupies on `buffer_line`, as 0-based
--- offsets suitable for an extmark.
---@param buffer_line integer
---@param column_number integer
---@return integer|nil from
---@return integer|nil to
function Page:cell_bounds(buffer_line, column_number)
  local range = self:cell_ranges(buffer_line)[column_number]
  if not range then
    return nil, nil
  end
  return range.from, range.to
end

--- How wide column `column_number` is drawn, in characters, once the padding
--- around every value is taken back off. Every line pads its cells to the same
--- width, so the header answers for all of them.
---@param column_number integer
---@return integer|nil
function Page:cell_width(column_number)
  local range = self.ranges[column_number]
  if not range then
    return nil
  end
  local header = self.lines[self.header_line]
  return text.length(header:sub(range.from + 1, range.to)) - CELL_PADDING
end

--- Which column of `buffer_line` holds byte offset `byte`. A byte on a separator
--- answers with the column to its right, and a byte past the last cell answers
--- with the last column, so every byte of the line names a column.
---@param buffer_line integer
---@param byte integer 0-based, as nvim reports the cursor.
---@return integer column_number
function Page:column_number_at(buffer_line, byte)
  local ranges = self:cell_ranges(buffer_line)
  for column_number, range in ipairs(ranges) do
    if byte < range.to then
      return column_number
    end
  end
  return #ranges
end

--- The row drawn on `buffer_line`, present for the data lines.
---@param buffer_line integer
---@return csv.Row|nil
function Page:row_at_line(buffer_line)
  return self.rows_by_line[buffer_line]
end

---@param row_id integer
---@return csv.Row|nil
function Page:row_by_id(row_id)
  return self.rows_by_id[row_id]
end

---@param row_number integer
---@return csv.Row|nil
function Page:row_by_number(row_number)
  return self.rows_by_number[row_number]
end

---@param column_number integer
---@return csv.Column|nil
function Page:column_at(column_number)
  return self.columns[column_number]
end

--- The cell `ref` names here, absent once the row or the column has left the page.
---@param ref csv.CellRef|nil
---@return csv.Cell|nil
function Page:cell_of(ref)
  if not ref then
    return nil
  end
  local row = self:row_by_id(ref.row_id)
  local column = self:column_by_id(ref.column_id)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

---@param column_id integer
---@return csv.Column|nil
function Page:column_by_id(column_id)
  local column_number = self.column_number_by_id[column_id]
  return column_number and self.columns[column_number] or nil
end

--- Where `column` is drawn, present while it is on display.
---@param column csv.Column
---@return integer|nil column_number
function Page:column_number(column)
  return self.column_number_by_id[column.column_id]
end

---@return integer
function Page:column_count()
  return #self.columns
end

---@return integer
function Page:row_count()
  return self.last_line - self.first_line + 1
end

--- Where `cell` lands when it is taken `rows` down and `columns` across, kept
--- inside the table.
---@param cell csv.Cell
---@param delta { rows: integer, columns: integer }
---@return csv.Cell|nil
function Page:step_cell(cell, delta)
  local column_number = self:column_number(cell.column)
  if not column_number then
    return nil
  end

  local line = math.min(
    math.max(cell.row.buffer_line + delta.rows, self.first_line),
    self.last_line
  )
  local number = math.min(math.max(column_number + delta.columns, 1), self:column_count())

  local row = self:row_at_line(line)
  local column = self:column_at(number)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

--- The cell drawn at `line` and byte `byte`. A line holding a border or the
--- header answers with the nearest data line, so every position in a drawn table
--- names a cell.
---@param line integer
---@param byte integer 0-based, as nvim reports a cursor.
---@return csv.Cell|nil
function Page:cell_at(line, byte)
  if self.first_line > self.last_line then
    return nil
  end

  local buffer_line = math.min(math.max(line, self.first_line), self.last_line)
  local column_number = math.min(self:column_number_at(buffer_line, byte), self:column_count())

  local row = self:row_at_line(buffer_line)
  local column = self:column_at(column_number)
  if not row or not column then
    return nil
  end
  return { row = row, column = column }
end

return M
