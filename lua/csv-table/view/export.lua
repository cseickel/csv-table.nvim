--[[
The `csv.View` method that writes the selected cells to the clipboard.

Every format but `display` is written by the reader from the file, so a column
narrow enough to have been drawn cut still exports whole. `display` is the text the
buffer already holds, so a value drawn cut is exported cut.
]]

local report = require("csv-table.utils.report")

local M = {}

--- Write `text` to both `+` and `"`, so `p` inside nvim pastes it whether or not
--- `clipboard` follows the system one.
---@param text string
local function to_registers(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

--- The rows and columns `bounds` covers, as row ids and columns, nil once any of
--- them has left the page.
---@param bounds csv.Bounds
---@return csv.Block|nil
local function block_of(self, bounds)
  local current_page = self.buffer.page

  local columns = {}
  for column_number = bounds.left, bounds.right do
    local column = current_page:column_at(column_number)
    if not column then
      return nil
    end
    columns[#columns + 1] = column
  end

  local row_ids = {}
  for buffer_line = bounds.top, bounds.bottom do
    local row = current_page:row_at_line(buffer_line)
    if not row then
      return nil
    end
    row_ids[#row_ids + 1] = row.row_id
  end

  return { row_ids = row_ids, columns = columns }
end

--- The selected cells as the table draws them, one line each, the header line
--- first. Each line is cut at its own cell ranges, because a line holding a
--- multi-byte character has its separators at byte offsets the header does not
--- share.
---@param bounds csv.Bounds
---@param headers boolean
---@return string
local function drawn_text(self, bounds, headers)
  local current_page = self.buffer.page
  local lines = {}

  ---@param buffer_line integer
  local function cut(buffer_line)
    local ranges = current_page:cell_ranges(buffer_line)
    local first, last = ranges[bounds.left], ranges[bounds.right]
    if first and last then
      table.insert(lines, current_page.lines[buffer_line]:sub(first.from + 1, last.to))
    end
  end

  if headers then
    cut(current_page.header_line)
  end
  for buffer_line = bounds.top, bounds.bottom do
    cut(buffer_line)
  end
  return table.concat(lines, "\n")
end

--- Copy the selected cells, or the active cell when nothing is selected. One cell
--- is copied as its bare value, trimmed, whatever the format: `display` gives the
--- text drawn and every other format the value the file holds.
---@param opts { format: "tsv"|"csv"|"json"|"markdown"|"display", headers: boolean }
function M.yank(self, opts)
  local bounds = self:bounds() or self:active_bounds()
  if not bounds then
    return report.error("there is nothing to yank")
  end

  local rows = bounds.bottom - bounds.top + 1
  local columns = bounds.right - bounds.left + 1
  local function done()
    vim.notify(string.format("csv-table: yanked %d rows by %d columns", rows, columns))
  end

  local one_cell = rows == 1 and columns == 1
  if opts.format == "display" then
    if one_cell then
      to_registers(vim.trim(drawn_text(self, bounds, false)))
    else
      to_registers(drawn_text(self, bounds, opts.headers))
    end
    return done()
  end

  local block = block_of(self, bounds)
  if not block then
    return report.error("the selected cells are no longer on display")
  end

  local query = self.buffer.query
  if one_cell then
    local ref = { row_id = block.row_ids[1], column_id = block.columns[1].column_id }
    return query.reader:cell(query, ref, function(value)
      to_registers(vim.trim(value))
      done()
    end)
  end

  query.reader:export(query, {
    block = block,
    format = opts.format,
    headers = opts.headers,
  }, function(text)
    to_registers(text)
    done()
  end)
end

return M
