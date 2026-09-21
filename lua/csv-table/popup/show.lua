--[[
Shows what a cell or a row holds, read back from the file. A value wider than its
column is drawn cut, so the text on screen cannot answer what a cell holds.
]]

local json = require("csv-table.utils.json")
local picker = require("csv-table.popup.picker")
local popup = require("csv-table.popup")
local text = require("csv-table.utils.text")

local M = {}

local GAP = "  "

---@param value string
---@return string[] lines
---@return boolean is_json
local function value_lines(value)
  if json.is_json(value) then
    return json.indent(value), true
  end
  return vim.split(value, "\n", { plain = true }), false
end

---@param view csv.View
function M.cell(view)
  local cell = view:active_cell()
  if not cell then
    return
  end

  local query = view.buffer.query
  local ref = { row_id = cell.row.row_id, column_id = cell.column.column_id }
  query.reader:cell(query, ref, function(value)
    local lines, is_json = value_lines(value)
    local bufnr = popup.open(lines, { title = cell.column.label, wrap = true })
    if is_json then
      vim.bo[bufnr].filetype = "json"
    end
  end)
end

--- Search the active cell's row by column name or value, and copy what is chosen.
--- A file wide enough that the column you want has scrolled off the screen is read
--- this way rather than by moving to the cell.
---
--- The cell is read before xan runs, so a panel opened over a row the user has
--- since left still says which row it is showing.
---@param view csv.View
function M.row(view)
  local cell = view:active_cell()
  if not cell then
    return
  end

  local query = view.buffer.query
  query.reader:row_values(query, cell.row.row_id, function(values)
    -- `file.columns` holds the hidden columns too, so the row comes out whole.
    local fields = {}
    local width = 0
    for index, column in ipairs(query.file.columns) do
      fields[index] = { name = column.label, value = values[column.column_id] or "" }
      width = math.max(width, text.length(column.label))
    end

    picker.choose(fields, {
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
