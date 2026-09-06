--[[
The values behind the table.

A value wider than its column is drawn cut, so the text on screen cannot answer
what a cell holds. Both of these read the row from the file through
`csv-table.query`, so every value is the one in the source, at full length and
before any formatting.

`cell` shows one value to be read, `row` offers the whole row to be searched and
copies whatever is chosen, and `copy` takes the selected cells as tab separated
text, which is what a spreadsheet pastes as cells.
]]

local columns = require("csv-table.columns")
local cursor = require("csv-table.cursor")
local json = require("csv-table.json")
local picker = require("csv-table.picker")
local query = require("csv-table.query")
local range = require("csv-table.range")
local selection = require("csv-table.selection")
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

--- Read the row the cursor is on. The row id goes to `on_row` as well, because
--- the cursor may have moved while xan ran. Nothing happens before the first
--- paint, when there is no row to be on.
---@param buf csv.Buffer
---@param on_row fun(row: table<string, string>, rowid: integer)
local function with_row(buf, on_row)
  local cell = cursor.cell_ref(buf, 0)
  if not cell then
    return
  end
  query.row(buf.state, cell.row, query.report, function(row)
    on_row(row, cell.row)
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

--- Hold `text` for pasting, in the system clipboard and in the unnamed register,
--- so `p` inside nvim pastes it whether or not `clipboard` is set to follow the
--- system one.
---@param text string
local function hold(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

--- One field of tab separated text. A value holding a tab or a newline would
--- otherwise read as another field or another row, so it is quoted the way a
--- spreadsheet reads it back.
---@param value string
---@return string
local function tsv_field(value)
  if value:find('[\t\n\r"]') then
    return '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

--- What copying should take: the selected cells, or the cell under the cursor
--- when nothing is selected.
---@param buf csv.Buffer
---@return csv.Bounds|nil
local function block(buf)
  local painted = buf.layout
  if not painted then
    return nil
  end

  local bounds = range.bounds(buf.state, painted)
  if bounds then
    return bounds
  end

  local cell = cursor.cell_ref(buf, 0)
  local line = cell and painted.lines_by_rowid[cell.row]
  if not line then
    return nil
  end
  return { top = line, bottom = line, left = cell.column, right = cell.column }
end

--- Copy the selected cells as tab separated text, which is what a spreadsheet
--- pastes as cells. The values come from the file, so a column narrow enough to
--- have been drawn cut still copies whole.
---@param buf csv.Buffer
---@param excludeHeaders boolean
function M.copy(buf, excludeHeaders)
  local bounds = block(buf)
  if not bounds then
    return query.report("there is nothing to copy")
  end

  local shown = selection.selected(buf.state)
  local wanted = {}
  for position = bounds.left, bounds.right do
    local column = shown[position]
    if not column then
      return query.report("the selected columns are no longer on display")
    end
    wanted[#wanted + 1] = column
  end

  local rows, across = range.size(bounds)
  local opts = { first = bounds.top - buf.layout.first_row, count = rows, columns = wanted }

  query.cells(buf.state, opts, query.report, function(fetched)
    local lines = {}
    for index, row in ipairs(fetched) do
      local fields = {}
      for position, column in ipairs(wanted) do
        fields[position] = tsv_field(value_of(row, columns.display(column)))
      end
      lines[index] = table.concat(fields, "\t")
    end

    hold(table.concat(lines, "\n"))
    vim.notify(string.format("csv-table: copied %d rows by %d columns", #lines, across))
  end)
end

--- Search the row under the cursor by column name or by value, and copy what is
--- chosen. A row is read by searching it once a file is wide enough that the
--- column wanted is off the screen.
---@param buf csv.Buffer
function M.row(buf)
  with_row(buf, function(row, rowid)
    local values = named_values(buf, row)

    local width = 0
    for _, named in ipairs(values) do
      width = math.max(width, columns.text_length(named.name))
    end

    picker.choose(values, {
      prompt = "row " .. rowid,
      format_item = function(named)
        local padding = string.rep(" ", width - columns.text_length(named.name))
        return named.name .. padding .. GAP .. named.value:gsub("%s+", " ")
      end,
    }, function(named)
      hold(named.value)
      vim.notify("csv-table: copied " .. named.name)
    end)
  end)
end

return M
