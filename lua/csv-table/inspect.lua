--[[
Reads values back out of the file, since a value wider than its column is drawn
cut and the text on screen cannot answer what a cell holds.

- `cell` opens what the active cell holds, at full length
- `row` offers every column of the row to be searched, and copies the choice
- `yank` writes the selected cells to the clipboard as tsv, csv, json, markdown
  or `display`

`display` is the one format taken from the buffer rather than the file, so a
value drawn cut is yanked cut.
]]

local columns = require("csv-table.columns")
local active_cell = require("csv-table.active_cell")
local json = require("csv-table.json")
local layout_module = require("csv-table.layout")
local picker = require("csv-table.picker")
local reader = require("csv-table.reader")
local selection = require("csv-table.selection")
local state = require("csv-table.state")
local window = require("csv-table.window")

local M = {}

local GAP = "  "

--- What `column` holds in the row `values` came from. The values are in file
--- order and a column id is a position in that order counting from zero.
---@param values string[]
---@param column csv.Column
---@return string
local function value_of(values, column)
  return values[column.column_id + 1] or ""
end

--- How one value reads in a panel, and whether it came out as JSON.
---@param value string
---@return string[] lines
---@return boolean is_json
local function value_lines(value)
  if json.is_json(value) then
    return json.indent(value), true
  end
  return vim.split(value, "\n", { plain = true }), false
end

---@class csv.NamedValue
---@field name string Display name of the column.
---@field value string

--- Every column of the row, in file order, so a column hidden from the table is
--- still answered for.
---@param buf csv.Buffer
---@param values string[]
---@return csv.NamedValue[]
local function named_values(buf, values)
  local named = {}
  for index, column in ipairs(state.source_order(buf.state)) do
    named[index] = { name = column.label, value = value_of(values, column) }
  end
  return named
end

--- Read the row the active cell is in, and hand back the cell along with it.
---
--- The cell is the one under the cursor when the read starts, so a panel opened
--- over a row the user has since left still shows the row it was asked for.
---@param buf csv.Buffer
---@param on_row fun(values: string[], cell: csv.Cell)
local function read_row(buf, on_row)
  local cell = active_cell.cell(buf, 0)
  if not cell then
    return
  end

  buf.reader:row_values(buf.state, cell.row.row_id, reader.report, function(values)
    on_row(values, cell)
  end)
end

--- Show what the active cell holds, at full length.
---@param buf csv.Buffer
function M.cell(buf)
  read_row(buf, function(values, cell)
    local lines, is_json = value_lines(value_of(values, cell.column))
    local bufnr = window.open(lines, { title = cell.column.label, wrap = true })
    if is_json then
      vim.bo[bufnr].filetype = "json"
    end
  end)
end

--- Put `text` in the system clipboard and the unnamed register, so `p` inside
--- nvim pastes it whether or not `clipboard` is set to follow the system one.
---@param text string
local function to_registers(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

--- What a yank takes: the selected cells while a selection is set, and the
--- active cell on its own otherwise.
---@param buf csv.Buffer
---@return csv.Bounds|nil
local function yank_bounds(buf)
  local layout = buf.layout
  if not layout then
    return nil
  end

  local bounds = selection.bounds(buf.state, layout)
  if bounds then
    return bounds
  end

  local cell = active_cell.cell(buf, 0)
  if not cell then
    return nil
  end
  local column_number = layout_module.column_number(layout, cell.column)
  return {
    top = cell.row.buffer_line,
    bottom = cell.row.buffer_line,
    left = column_number,
    right = column_number,
  }
end

--- The selected cells exactly as the table draws them, one line each, the header
--- line first. This is the only format that stays in the buffer: a value its
--- column draws cut is yanked cut, which is what makes it what you see.
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
    local cells = layout_module.cell_ranges(buf.layout, buffer_line)
    local first, last = cells[bounds.left], cells[bounds.right]
    if first and last then
      table.insert(lines, buf.layout.lines[buffer_line]:sub(first.from + 1, last.to))
    end
  end

  if headers then
    cut(buf.layout.header_line)
  end
  for buffer_line = bounds.top, bounds.bottom do
    cut(buffer_line)
  end
  return table.concat(lines, "\n")
end

--- Yank the selected cells in `format`, which is one of the names
--- `csv-table.reader.commands` writes: `tsv`, `csv`, `json`, `markdown`, or
--- `display`.
---
--- Every format but `display` reads the values from the file through xan, so a
--- column narrow enough to have been drawn cut still yanks whole, and a value
--- holding a tab or a newline comes out quoted.
---@param buf csv.Buffer
---@param format string
---@param headers boolean Whether to put the column names above the cells.
function M.yank(buf, format, headers)
  local bounds = yank_bounds(buf)
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

  local yanked = {}
  for column_number = bounds.left, bounds.right do
    local column = layout_module.column_at(buf.layout, column_number)
    if not column then
      return reader.report("the selected columns are no longer on display")
    end
    yanked[#yanked + 1] = column
  end

  local rowids = {}
  for buffer_line = bounds.top, bounds.bottom do
    local row = layout_module.row_at_line(buf.layout, buffer_line)
    if not row then
      return reader.report("the selected rows are no longer on display")
    end
    rowids[#rowids + 1] = row.row_id
  end

  local opts = { rowids = rowids, columns = yanked, headers = headers, format = format }
  buf.reader:yank(buf.state, opts, reader.report, function(text)
    to_registers(text)
    done()
  end)
end

--- Search the active cell's row by column name or by value, and copy what is
--- chosen. A row is read by searching it once a file is wide enough that the
--- column being read is off the screen.
---@param buf csv.Buffer
function M.row(buf)
  read_row(buf, function(values, cell)
    local named = named_values(buf, values)

    local width = 0
    for _, field in ipairs(named) do
      width = math.max(width, columns.text_length(field.name))
    end

    picker.choose(named, {
      prompt = "row " .. cell.row.row_number,
      format_item = function(field)
        local padding = string.rep(" ", width - columns.text_length(field.name))
        return field.name .. padding .. GAP .. field.value:gsub("%s+", " ")
      end,
    }, function(field)
      to_registers(field.value)
      vim.notify("csv-table: copied " .. field.name)
    end)
  end)
end

return M
