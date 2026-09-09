--[[
Writes the selected cells to the clipboard.

Every format but `display` is written by the reader from the file, so a column
narrow enough to have been drawn cut still exports whole. `display` is the text
the buffer already holds, so a value drawn cut is exported cut.
]]

local cursor = require("csv-table.buffer.cursor")
local reader = require("csv-table.reader")

local M = {}

--- Put `text` in the system clipboard and the unnamed register, so `p` inside
--- nvim pastes it whether or not `clipboard` is set to follow the system one.
---@param text string
local function to_registers(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

--- What an export takes: the selected cells while a selection is set, and the
--- active cell on its own otherwise.
---@param buf csv.Buffer
---@return csv.Bounds|nil
local function bounds_of(buf)
  local bounds = buf.query:selection_bounds(buf.page)
  if bounds then
    return bounds
  end

  local cell = cursor.cell(buf, 0)
  if not cell then
    return nil
  end
  local column_number = buf.page:column_number(cell.column)
  return {
    top = cell.row.buffer_line,
    bottom = cell.row.buffer_line,
    left = column_number,
    right = column_number,
  }
end

--- The rows and columns `bounds` covers, named the way the reader names them.
---@param buf csv.Buffer
---@param bounds csv.Bounds
---@return csv.Block|nil
local function block_of(buf, bounds)
  local columns = {}
  for column_number = bounds.left, bounds.right do
    local column = buf.page:column_at(column_number)
    if not column then
      return nil
    end
    columns[#columns + 1] = column
  end

  local row_ids = {}
  for buffer_line = bounds.top, bounds.bottom do
    local row = buf.page:row_at_line(buffer_line)
    if not row then
      return nil
    end
    row_ids[#row_ids + 1] = row.row_id
  end

  return { row_ids = row_ids, columns = columns }
end

--- The selected cells exactly as the table draws them, one line each, the header
--- line first.
---
--- Each line is cut at its own cell ranges, because a line holding a multi-byte
--- character has its separators at byte offsets the header does not share.
---@param buf csv.Buffer
---@param bounds csv.Bounds
---@param headers boolean
---@return string
local function drawn_text(buf, bounds, headers)
  local lines = {}

  ---@param buffer_line integer
  local function cut(buffer_line)
    local cells = buf.page:cell_ranges(buffer_line)
    local first, last = cells[bounds.left], cells[bounds.right]
    if first and last then
      table.insert(lines, buf.page.lines[buffer_line]:sub(first.from + 1, last.to))
    end
  end

  if headers then
    cut(buf.page.header_line)
  end
  for buffer_line = bounds.top, bounds.bottom do
    cut(buffer_line)
  end
  return table.concat(lines, "\n")
end

--- Export the selected cells in `format`, which is `tsv`, `csv`, `json`,
--- `markdown` or `display`.
---@param buf csv.Buffer
---@param format string
---@param headers boolean Whether to put the column names above the cells.
function M.yank(buf, format, headers)
  local bounds = bounds_of(buf)
  if not bounds then
    return reader.report("there is nothing to yank")
  end

  local rows = bounds.bottom - bounds.top + 1
  local wide = bounds.right - bounds.left + 1
  local function done()
    vim.notify(string.format("csv-table: yanked %d rows by %d columns", rows, wide))
  end

  if format == "display" then
    to_registers(drawn_text(buf, bounds, headers))
    return done()
  end

  local block = block_of(buf, bounds)
  if not block then
    return reader.report("the selected cells are no longer on display")
  end

  buf.query.reader:export(buf.query, {
    block = block,
    format = format,
    headers = headers,
  }, function(text)
    to_registers(text)
    done()
  end)
end

return M
