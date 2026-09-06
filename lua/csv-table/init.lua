--[[
Entry point.

A spreadsheet file is intercepted before nvim reads it. The buffer shows `xan
view` output, rendered from view state on every change, so the size of the
file does not matter.

`setup` merges `keymaps` over the default bindings and replaces `patterns` and
`page_size`.
]]

local actions = require("csv-table.actions")
local buffer = require("csv-table.buffer")
local columns = require("csv-table.columns")
local cursor = require("csv-table.cursor")
local highlight = require("csv-table.highlight")
local keymaps = require("csv-table.keymaps")
local state = require("csv-table.state")

local M = {}

M.patterns = { "*.csv", "*.tsv", "*.xls", "*.xlsx", "*.xlsb", "*.ods" }

---@param buf csv.Buffer
local function apply_keymaps(buf)
  for key, name in pairs(keymaps.map) do
    if name then
      local action = actions.get_action(name)
      if not action then
        error(string.format("csv-table: key %q names unknown action %q", key, name))
      end
      vim.keymap.set("n", key, function()
        action.run(buf)
      end, { buffer = buf.bufnr, desc = "csv-table: " .. action.description })
    end
  end
end

local SHEET_NAME_LENGTH = 10

--- Which sheet of a workbook is on screen, and the key that changes it. Absent
--- for a source that has no sheets.
---@param buf csv.Buffer
---@return string|nil
local function sheet_summary(buf)
  local sheets = buf.state.sheets
  if #sheets == 0 then
    return nil
  end

  local name = sheets[buf.state.sheet + 1] or ""
  return string.format(
    "sheet %d/%d %s · gS sheets",
    buf.state.sheet + 1,
    #sheets,
    columns.truncate(name, SHEET_NAME_LENGTH)
  )
end

--- What the sort reads as in a statusline.
---@param buf csv.Buffer
---@return string|nil
local function sort_summary(buf)
  if #buf.state.sort_keys == 0 then
    return nil
  end

  local parts = {}
  for index, key in ipairs(buf.state.sort_keys) do
    parts[index] = columns.display(key.column) .. (key.direction == "asc" and "▲" or "▼")
  end
  return "sort " .. table.concat(parts, " ")
end

--- What is held for pasting, as a statusline fragment.
---@param buf csv.Buffer
---@return string|nil
local function clipboard_summary(buf)
  if #buf.state.clipboard == 0 then
    return nil
  end

  local names = {}
  for index, column in ipairs(buf.state.clipboard) do
    names[index] = columns.display(column)
  end
  return "cut " .. table.concat(names, ",")
end

--- How the page and everything applied to it read in a statusline. Empty for
--- any buffer that is not a table.
---@param bufnr integer
---@return string
function M.status(bufnr)
  local buf = buffer.get(bufnr)
  if not buf or not buf.layout then
    return ""
  end

  local parts = { sheet_summary(buf) }
  local first, last = buffer.row_range(buf)
  if last < first then
    table.insert(parts, "no rows")
  elseif buffer.at_last_page(buf) then
    table.insert(parts, string.format("rows %d-%d (end)", first, last))
  else
    table.insert(parts, string.format("rows %d-%d", first, last))
  end

  if #buf.state.filters > 0 then
    table.insert(parts, #buf.state.filters == 1 and "1 filter" or (#buf.state.filters .. " filters"))
  end

  local marked_count = vim.tbl_count(buf.state.marked)
  if marked_count > 0 then
    table.insert(parts, marked_count .. " marked")
  end

  table.insert(parts, sort_summary(buf))
  table.insert(parts, clipboard_summary(buf))
  table.insert(parts, "? help")
  return table.concat(parts, " · ")
end

---@param opts { keymaps: table<string, string|false>|nil, patterns: string[]|nil, page_size: integer|nil }|nil
function M.setup(opts)
  opts = opts or {}
  if opts.keymaps then
    keymaps.map = vim.tbl_extend("force", keymaps.map, opts.keymaps)
  end
  if opts.patterns then
    M.patterns = opts.patterns
  end
  if opts.page_size then
    if type(opts.page_size) ~= "number" or opts.page_size < 1 then
      error("csv-table: page_size must be a number of rows, 1 or more")
    end
    state.page_size = math.floor(opts.page_size)
  end

  -- One group for every autocommand that lasts the session, so a second `setup`
  -- replaces what the first left rather than adding to it. The ones a table
  -- buffer owns are in `csv-table-buffer`.
  local group = vim.api.nvim_create_augroup("csv-table", { clear = true })
  highlight.setup(group)
  cursor.setup(group)

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = M.patterns,
    callback = function(event)
      buffer.attach(event.buf, apply_keymaps)
    end,
  })

  vim.api.nvim_create_user_command("CsvTable", function(command)
    local path = command.args ~= "" and command.args or vim.api.nvim_buf_get_name(0)
    if path == "" then
      return vim.notify("csv-table: no file to open", vim.log.levels.ERROR)
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
  end, { nargs = "?", complete = "file", desc = "Open a CSV as a table" })
end

return M
