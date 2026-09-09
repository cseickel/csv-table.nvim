--[[
Shows what a cell or a row holds, read back from the file, since a value wider
than its column is drawn cut and the text on screen cannot answer what a cell
holds.

- `cell` opens what the active cell holds, at full length
- `row` offers every column of the row to be searched, and copies the choice
]]

local cursor = require("csv-table.buffer.cursor")
local json = require("csv-table.utils.json")
local picker = require("csv-table.popup.picker")
local popup = require("csv-table.popup")
local text = require("csv-table.utils.text")

local M = {}

local GAP = "  "

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

--- Show what the active cell holds, at full length.
---@param buf csv.Buffer
function M.cell(buf)
  local cell = cursor.active_cell(buf, 0)
  if not cell then
    return
  end

  local ref = { row_id = cell.row.row_id, column_id = cell.column.column_id }
  buf.query.reader:cell(buf.query, ref, function(value)
    local lines, is_json = value_lines(value)
    local bufnr = popup.open(lines, { title = cell.column.label, wrap = true })
    if is_json then
      vim.bo[bufnr].filetype = "json"
    end
  end)
end

--- Search the active cell's row by column name or by value, and copy what is
--- chosen. A row is read by searching it once a file is wide enough that the
--- column being read is off the screen.
---
--- The cell is read before xan runs, so a panel opened over a row the user has
--- since left still says which row it is showing.
---@param buf csv.Buffer
function M.row(buf)
  local cell = cursor.active_cell(buf, 0)
  if not cell then
    return
  end

  buf.query.reader:row_values(buf.query, cell.row.row_id, function(values)
    -- Every column of the file, in file order, so a column hidden from the table
    -- is still answered for.
    local named = {}
    local width = 0
    for index, column in ipairs(buf.query.file.columns) do
      named[index] = { name = column.label, value = values[column.column_id] or "" }
      width = math.max(width, text.length(column.label))
    end

    picker.choose(named, {
      prompt = "row " .. cell.row.row_number,
      format_item = function(field)
        local padding = string.rep(" ", width - text.length(field.name))
        return field.name .. padding .. GAP .. field.value:gsub("%s+", " ")
      end,
    }, function(field)
      vim.fn.setreg("+", field.value)
      vim.fn.setreg('"', field.value)
      vim.notify("csv-table: copied " .. field.name)
    end)
  end)
end

return M
