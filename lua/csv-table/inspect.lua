--[[
The values behind the table.

A value wider than its column is drawn cut, so the text on screen cannot answer
what a cell holds. Everything here goes back to the file through
`csv-table.query`, so every value is the one in the source, at full length and
before any formatting.

`cell` shows one value to be read, `row` offers the whole row to be searched and
copies whatever is chosen, and `copy` takes the selected cells as tab separated
text, which is what a spreadsheet pastes as cells.
]]

local columns = require("csv-table.columns")
local active_cell = require("csv-table.active_cell")
local json = require("csv-table.json")
local picker = require("csv-table.picker")
local query = require("csv-table.query")
local range = require("csv-table.range")
local selection = require("csv-table.selection")
local state = require("csv-table.state")
local window = require("csv-table.window")

local M = {}

local GAP = "  "

--- What one column holds in this row. `to jsonl --strings '*'` asks xan for
--- every value as a string, and `csv-table.format` already declines to trust
--- that, so this declines too.
---@param row table<string, string>
---@param name string
---@return string
local function value_of(row, name)
  local value = row[name]
  return type(value) == "string" and value or ""
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
---@param row table<string, string>
---@return csv.NamedValue[]
local function named_values(buf, row)
  local values = {}
  for index, column in ipairs(buf.state.columns) do
    local name = columns.display(column)
    values[index] = { name = name, value = value_of(row, name) }
  end
  return values
end

--- Read the row the cursor is on. The number that row is drawn with goes to
--- `on_row` as well, because the cursor may have moved while xan ran, and it is
--- the number rather than the row id because the row id is not on screen to be
--- recognized. Nothing happens before the first render, when there is no row to
--- be on.
---@param buf csv.Buffer
---@param on_row fun(row: table<string, string>, number: integer)
local function with_row(buf, on_row)
  local cell = active_cell.cell_ref(buf, 0)
  if not cell then
    return
  end

  local line = buf.layout.row_index_by_id[cell.row]
  local number = state.first_row_number(buf.state) + line - buf.layout.first_row
  query.row(buf.state, cell.row, query.report, function(row)
    on_row(row, number)
  end)
end

--- Show what the cell under the cursor holds.
---@param buf csv.Buffer
---@param column csv.Column
function M.cell(buf, column)
  local name = columns.display(column)
  with_row(buf, function(row)
    local lines, json = value_lines(value_of(row, name))
    local bufnr = window.open(lines, { title = name, wrap = true })
    if json then
      vim.bo[bufnr].filetype = "json"
    end
  end)
end

--- Yank `text` into the system clipboard and the unnamed register, so `p` inside
--- nvim pastes it whether or not `clipboard` is set to follow the system one.
---@param text string
local function yank(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

--- What copying should take: the selected cells, or the cell under the cursor
--- when nothing is selected.
---@param buf csv.Buffer
---@return csv.Bounds|nil
local function copy_bounds(buf)
  local layout = buf.layout
  if not layout then
    return nil
  end

  local bounds = range.bounds(buf.state, layout)
  if bounds then
    return bounds
  end

  local cell = active_cell.cell_ref(buf, 0)
  local line = cell and layout.row_index_by_id[cell.row]
  if not line then
    return nil
  end
  return { top = line, bottom = line, left = cell.column, right = cell.column }
end

--- Copy the selected cells as tab separated text, which is what a spreadsheet
--- pastes as cells. `xan` reads the values from the file and writes the text, so
--- a column narrow enough to have been drawn cut still copies whole and a value
--- holding a tab or a newline comes out quoted.
---@param buf csv.Buffer
---@param headers boolean Whether to put the column names above the cells.
function M.copy(buf, headers)
  local bounds = copy_bounds(buf)
  if not bounds then
    return query.report("there is nothing to copy")
  end

  local displayed = selection.display_columns(buf.state)
  local copied = {}
  for position = bounds.left, bounds.right do
    local column = displayed[position]
    if not column then
      return query.report("the selected columns are no longer on display")
    end
    copied[#copied + 1] = column
  end

  local rowids = {}
  for line = bounds.top, bounds.bottom do
    local rowid = buf.layout.row_id_by_index[line]
    if not rowid then
      return query.report("the selected rows are no longer on display")
    end
    rowids[#rowids + 1] = rowid
  end

  local opts = { rowids = rowids, columns = copied, headers = headers }
  query.copy(buf.state, opts, query.report, function(text)
    yank(text)
    vim.notify(string.format("csv-table: copied %d rows by %d columns", #rowids, #copied))
  end)
end

--- Search the row under the cursor by column name or by value, and copy what is
--- chosen. A row is read by searching it once a file is wide enough that the
--- column being read is off the screen.
---@param buf csv.Buffer
function M.row(buf)
  with_row(buf, function(row, number)
    local values = named_values(buf, row)

    local width = 0
    for _, field in ipairs(values) do
      width = math.max(width, columns.text_length(field.name))
    end

    picker.choose(values, {
      prompt = "row " .. number,
      format_item = function(field)
        local padding = string.rep(" ", width - columns.text_length(field.name))
        return field.name .. padding .. GAP .. field.value:gsub("%s+", " ")
      end,
    }, function(field)
      yank(field.value)
      vim.notify("csv-table: copied " .. field.name)
    end)
  end)
end

return M
