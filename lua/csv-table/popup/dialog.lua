--[[
Opens the two dialogs that add a filter or change the sheet.

- `open` offers the comparisons that suit the column's kind, a checklist of the
  column's own values, or a moonblade expression
- `sheets` lists a workbook's sheets and reads the one chosen

The value checklist is drawn through the filters already applied, so every value
it offers is one that would leave rows on screen.
]]

local buffer = require("csv-table.buffer")
local popup = require("csv-table.popup")
local report = require("csv-table.utils.report")

local M = {}

---@class csv.Choice
---@field key string
---@field label string
---@field type "numeric"|"string"
---@field operator string

---@type csv.Choice[]
local NUMERIC_CHOICES = {
  { key = ">", label = "greater than", type = "numeric", operator = ">" },
  { key = ")", label = "greater than or equal to", type = "numeric", operator = ">=" },
  { key = "<", label = "less than", type = "numeric", operator = "<" },
  { key = "(", label = "less than or equal to", type = "numeric", operator = "<=" },
  { key = "=", label = "equal to", type = "numeric", operator = "==" },
  { key = "!", label = "not equal to", type = "numeric", operator = "!=" },
}

---@type csv.Choice[]
local TEXT_CHOICES = {
  { key = "=", label = "equal to", type = "string", operator = "eq" },
  { key = "!", label = "not equal to", type = "string", operator = "ne" },
  { key = "~", label = "containing", type = "string", operator = "contains" },
  { key = "^", label = "starting with", type = "string", operator = "startswith" },
  { key = "$", label = "ending with", type = "string", operator = "endswith" },
  { key = "/", label = "matching a regular expression", type = "string", operator = "regex" },
}

--- Draw the checklist for the value picker.
---@param values csv.Frequency[]
---@param checked table<integer, boolean>
---@return string[]
local function checklist(values, checked)
  local lines = {}
  for index, entry in ipairs(values) do
    lines[index] =
      string.format("  [%s] %-40s %s", checked[index] and "x" or " ", entry.value, entry.count)
  end
  return lines
end

--- Choose values from the column's own contents. The float is an ordinary buffer,
--- so `/` searches the list the way it searches anything else.
---@param buf csv.Buffer
---@param column csv.Column
---@param values csv.Frequency[]
local function pick_values(buf, column, values)
  if #values == 0 then
    return report.error("no values in " .. column.label)
  end

  local checked = {}
  local bufnr, winid = popup.open(checklist(values, checked), {
    title = column.label .. "  (space toggles, enter applies)",
    modifiable = true,
  })

  local function redraw()
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, checklist(values, checked))
    vim.bo[bufnr].modifiable = false
  end
  redraw()

  vim.keymap.set("n", "<Space>", function()
    local line = vim.api.nvim_win_get_cursor(winid)[1]
    checked[line] = not checked[line] or nil
    redraw()
    vim.api.nvim_win_set_cursor(winid, { line, 0 })
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "<CR>", function()
    local filter_values = {}
    for index in pairs(checked) do
      table.insert(filter_values, values[index].value)
    end
    popup.close(winid)

    if #filter_values == 0 then
      return
    end
    table.sort(filter_values)
    buf.query:add_filter({ type = "in", column = column, values = filter_values })
    buffer.render(buf)
  end, { buffer = bufnr, nowait = true })
end

--- Ask for the value a comparison compares against, then apply it.
---@param buf csv.Buffer
---@param column csv.Column
---@param choice csv.Choice
local function ask_for_value(buf, column, choice)
  vim.ui.input({ prompt = column.label .. " " .. choice.label .. ": " }, function(answer)
    if answer == nil or answer == "" then
      return
    end

    if choice.type == "numeric" then
      local number = tonumber(answer)
      if not number then
        return report.error(answer .. " is not a number")
      end
      buf.query:add_filter({
        type = "numeric",
        column = column,
        operator = choice.operator,
        value = number,
      })
    else
      buf.query:add_filter({
        type = "string",
        column = column,
        operator = choice.operator,
        value = answer,
      })
    end
    buffer.render(buf)
  end)
end

--- Choose which sheet of a workbook to read.
---@param buf csv.Buffer
function M.sheets(buf)
  local file = buf.query.file
  if #file.sheets == 0 then
    return report.error(vim.fn.fnamemodify(file.path, ":t") .. " has no sheets")
  end

  local lines = {}
  for index, name in ipairs(file.sheets) do
    lines[index] = string.format("  %s %d  %s", index - 1 == file.sheet and "▸" or " ", index, name)
  end

  local bufnr, winid = popup.open(lines, { title = "Sheets" })
  vim.api.nvim_win_set_cursor(winid, { file.sheet + 1, 0 })

  vim.keymap.set("n", "<CR>", function()
    local sheet = vim.api.nvim_win_get_cursor(winid)[1] - 1
    popup.close(winid)
    if sheet ~= file.sheet then
      buffer.open_sheet(buf, sheet)
    end
  end, { buffer = bufnr, nowait = true })
end

--- Open the dialog for `column`.
---@param buf csv.Buffer
---@param column csv.Column
function M.open(buf, column)
  local choices = buf.query:is_numeric(column) and NUMERIC_CHOICES or TEXT_CHOICES

  local lines = {}
  for index, choice in ipairs(choices) do
    lines[index] = string.format("  %s   %s", choice.key, choice.label)
  end
  table.insert(lines, "")
  table.insert(lines, "  v   choose from the values in this column")
  table.insert(lines, "  e   a moonblade expression")

  local bufnr, winid = popup.open(lines, { title = "Filter " .. column.label })

  for _, choice in ipairs(choices) do
    vim.keymap.set("n", choice.key, function()
      popup.close(winid)
      ask_for_value(buf, column, choice)
    end, { buffer = bufnr, nowait = true })
  end

  vim.keymap.set("n", "v", function()
    popup.close(winid)
    buf.query.reader:frequency(buf.query, column, function(values)
      pick_values(buf, column, values)
    end)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "e", function()
    popup.close(winid)
    vim.ui.input({ prompt = "moonblade expression: " }, function(expression)
      if expression == nil or expression == "" then
        return
      end
      buf.query:add_filter({ type = "expr", expression = expression })
      buffer.render(buf)
    end)
  end, { buffer = bufnr, nowait = true })
end

return M
