--[[
The entry point, where a spreadsheet file is caught before nvim reads it.

- `setup` takes `keymaps`, `patterns` and `page_size`, then registers the
  `BufReadCmd` that hands a matching file to `buffer.attach`
- the `CsvTable` command opens a path as a table
- `status` is the statusline: the sheet, the rows on the page, the filters, the
  marks, the sort and the cut columns
]]

local actions = require("csv-table.actions")
local buffer = require("csv-table.buffer")
local color = require("csv-table.buffer.color")
local guicursor = require("csv-table.buffer.guicursor")
local keymaps = require("csv-table.keymaps")
local movement = require("csv-table.buffer.movement")
local query = require("csv-table.query")
local text = require("csv-table.utils.text")

local M = {}

M.patterns = { "*.csv", "*.tsv", "*.xls", "*.xlsx", "*.xlsb", "*.ods" }

---@param buf csv.Buffer
local function apply_keymaps(buf)
  for _, binding in ipairs(keymaps.resolve()) do
    local modes = binding.visual and { "n", "x" } or { "n" }

    if binding.command then
      vim.keymap.set(modes, binding.key, binding.command, {
        buffer = buf.bufnr,
        desc = "csv-table: nvim's " .. binding.command,
      })
    else
      local action = actions.get_action(binding.action)
      if not action then
        error(
          string.format("csv-table: key %q names unknown action %q", binding.key, binding.action)
        )
      end

      vim.keymap.set(modes, binding.key, function()
        action.run(buf)
      end, { buffer = buf.bufnr, desc = "csv-table: " .. action.description })
    end
  end

  -- A click lands exactly where it was pointed, and `csv-table.buffer.movement`
  -- needs to know that, since any other move that ends up in the cell it started
  -- in was a motion too small to leave the cell. The expression hands the key
  -- back so nvim still does the click itself.
  vim.keymap.set({ "n", "x" }, "<LeftMouse>", function()
    movement.click()
    return "<LeftMouse>"
  end, { buffer = buf.bufnr, expr = true, desc = "csv-table: follow the click" })
end

local SHEET_NAME_LENGTH = 10

--- Which sheet of a workbook is on screen, and the key that changes it. Absent
--- for a file that has no sheets.
---@param buf csv.Buffer
---@return string|nil
local function sheet_summary(buf)
  local file = buf.query.file
  if #file.sheets == 0 then
    return nil
  end

  return string.format(
    "sheet %d/%d %s · gS sheets",
    file.sheet + 1,
    #file.sheets,
    text.truncate(file.sheets[file.sheet + 1] or "", SHEET_NAME_LENGTH)
  )
end

--- What the sort reads as in a statusline.
---@param buf csv.Buffer
---@return string|nil
local function sort_summary(buf)
  if #buf.query.sort_keys == 0 then
    return nil
  end

  local parts = {}
  for index, key in ipairs(buf.query.sort_keys) do
    parts[index] = key.column.label .. (key.direction == "asc" and "▲" or "▼")
  end
  return "sort " .. table.concat(parts, " ")
end

--- What is held for pasting, as a statusline fragment.
---@param buf csv.Buffer
---@return string|nil
local function clipboard_summary(buf)
  if #buf.query.clipboard == 0 then
    return nil
  end

  local names = {}
  for index, column in ipairs(buf.query.clipboard) do
    names[index] = column.label
  end
  return "cut " .. table.concat(names, ",")
end

--- How the page and everything applied to it read in a statusline. Empty for any
--- buffer that is not a table.
---@param bufnr integer
---@return string
function M.status(bufnr)
  local buf = buffer.get(bufnr)
  if not buf then
    return ""
  end

  local parts = { sheet_summary(buf) }
  local first, last = buffer.row_range(buf)
  if last < first then
    table.insert(parts, "no rows")
  else
    table.insert(parts, string.format("rows %d-%d of %d", first, last, buf.query.row_count))
  end

  if #buf.query.filters > 0 then
    local count = #buf.query.filters
    table.insert(parts, count == 1 and "1 filter" or (count .. " filters"))
  end

  local marked_count = vim.tbl_count(buf.query.marked)
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
    query.page_size = math.floor(opts.page_size)
  end

  -- One group for every autocommand that lasts the session, so a second `setup`
  -- replaces what the first left rather than adding to it. The ones a table
  -- buffer owns are in `csv-table-buffer`.
  local group = vim.api.nvim_create_augroup("csv-table", { clear = true })
  color.setup(group)
  guicursor.setup(group)

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
