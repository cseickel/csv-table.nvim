--[[
Reads the table `xan view` drew and builds the `csv.Page` describing it.

`view` pads its output with a blank line at each end, and draws a top border, the
header, a border, the rows, and a bottom border. The blank lines go and the rest
reaches the buffer, so the table keeps its frame.

The row ids come out of the first cell before that cell is cut away, so every
range this returns describes the text the buffer will hold.

Pure Lua, so it runs without nvim.
]]

local page = require("csv-table.page")

local M = {}

local SEPARATOR = "│"

---@param value string
---@return string
local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The byte range of every cell on one line. The ends of the line bound the first
--- and last cells, and a zero width range is dropped, so a theme that draws the
--- outer border and one that leaves it off give the same count. `view` pads every
--- cell, so every real cell has width.
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

--- Whether `line` is one of the three horizontal borders. Every theme draws them
--- from dashes and corners, and the header and the data rows are the lines that
--- hold a vertical separator.
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

--- `line` without its first cell: the `width` characters the cell is drawn in and
--- the separator that closes them.
---
--- Counting characters is what lets one cut serve a border line as well as a row.
--- Every line spends the same number of characters on the cell, while a border
--- line spends three bytes on each of them and a row of digits spends one.
---@param line string
---@param border_width integer Characters of outer border ahead of the cell, 1 or 0.
---@param width integer Characters the cell is drawn in, padding included.
---@return string
local function without_first_cell(line, border_width, width)
  local from = byte_of_character(line, border_width + 1)
  local to = byte_of_character(line, border_width + width + 2)
  return line:sub(1, from - 1) .. line:sub(to)
end

--- Build the page out of what `xan view` printed.
---@param output string[]
---@param opts { columns: csv.Column[], first_row_number: integer, file_version: string }
---@return csv.Page|nil
---@return string|nil error
function M.page(output, opts)
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
        row_number = opts.first_row_number + buffer_line - first_line,
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
  for column_number, column in ipairs(opts.columns) do
    column_number_by_id[column.column_id] = column_number
  end

  local ranges = scan(lines[header_line])
  local ranges_by_line = {}

  -- Every column is drawn at one display width, so the header's ranges answer for
  -- most lines. A line holding a multi-byte character puts its separators at
  -- other byte offsets, and only those lines are kept.
  for buffer_line = first_line, last_line do
    local line_ranges = scan(lines[buffer_line])
    if not same_ranges(line_ranges, ranges) then
      ranges_by_line[buffer_line] = line_ranges
    end
  end

  return page.new({
    lines = lines,
    header_line = header_line,
    first_line = first_line,
    last_line = last_line,
    rows_by_number = rows_by_number,
    rows_by_id = rows_by_id,
    rows_by_line = rows_by_line,
    columns = opts.columns,
    column_number_by_id = column_number_by_id,
    ranges = ranges,
    ranges_by_line = ranges_by_line,
    file_version = opts.file_version,
  }),
    nil
end

return M
