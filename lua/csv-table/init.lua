--[[
The entry point, the module a user's config requires and calls `setup` on.
]]

local autocmds = require("csv-table.autocmds")
local buffer = require("csv-table.buffer")
local color = require("csv-table.buffer.color")
local keymaps = require("csv-table.keymaps")
local query = require("csv-table.query")
local text = require("csv-table.utils.text")

local M = {}

M.extensions = { "csv", "tsv", "xls", "xlsx", "xlsb", "ods" }

local SHEET_NAME_LENGTH = 10

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

--- The columns cut and waiting to be pasted.
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

--- The statusline text for `bufnr`, empty for a buffer that is not a table. Set
--- `statusline` to call this.
---@param bufnr integer
---@return string
function M.status(bufnr)
  local buf = buffer.get(bufnr)
  if not buf then
    return ""
  end

  local parts = { sheet_summary(buf) }
  local first, last = buf:row_range()
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

local DISABLE = "--disable"

--- Read the current buffer's file as text instead of as a table.
---
--- A buffer captured by `:CsvTable` stays text, because the capture goes with the
--- table. A name `extensions` covers comes back as a table on the next `:edit`,
--- because the read command registered over the extension is still there.
local function disable_current()
  local bufnr = vim.api.nvim_get_current_buf()
  if not buffer.get(bufnr) then
    return vim.notify("csv-table: this buffer is not a table", vim.log.levels.ERROR)
  end
  buffer.detach(bufnr)
end

--- An extension goes into an autocommand pattern, so anything nvim would read
--- there as glob syntax rather than as itself is refused.
---@param extension string
---@return boolean
local function valid_extension(extension)
  if extension == "" then
    return false
  end
  for part in vim.gsplit(extension, ".", { plain = true }) do
    if not part:match("^%w+$") then
      return false
    end
  end
  return true
end

---@param opts { keymaps: table<string, string|false>|nil, extensions: string[]|nil, page_size: integer|nil }|nil
function M.setup(opts)
  opts = opts or {}
  if opts.keymaps then
    keymaps.map = vim.tbl_extend("force", keymaps.map, opts.keymaps)
  end
  if opts.patterns then
    vim.notify(
      'csv-table: `patterns` is gone and was ignored. Use `extensions = { "csv", "jsonl" }`.',
      vim.log.levels.WARN
    )
  end
  if opts.extensions then
    for _, extension in ipairs(opts.extensions) do
      if not valid_extension(extension) then
        error(
          string.format(
            'csv-table: extensions holds %q. An entry is letters and digits, in parts '
              .. 'separated by single periods, as "csv" or "test.ps1".',
            extension
          )
        )
      end
    end
    M.extensions = opts.extensions
  end
  if opts.page_size then
    if type(opts.page_size) ~= "number" or opts.page_size < 1 then
      error("csv-table: page_size must be a number of rows, 1 or more")
    end
    query.page_size = math.floor(opts.page_size)
  end

  color.setup()
  autocmds.apply(M.extensions)

  vim.api.nvim_create_user_command("CsvTable", function(command)
    if command.args == DISABLE then
      return disable_current()
    end

    local path = command.args ~= "" and command.args or vim.api.nvim_buf_get_name(0)
    if path == "" then
      return vim.notify("csv-table: no file to open", vim.log.levels.ERROR)
    end

    -- `complete = "file"` backslash escapes a space, and the argument arrives as the
    -- user typed it. `expand` turns it back into a path.
    local full = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
    local stat = vim.uv.fs_stat(full)
    if not stat or stat.type ~= "file" then
      return vim.notify("csv-table: " .. full .. " is not a file", vim.log.levels.ERROR)
    end

    local bufnr = vim.fn.bufadd(full)
    -- nvim refuses to read over unsaved changes, and the read is what draws the
    -- table. Refusing here leaves the buffer as it was; capturing first would leave
    -- it half taken over.
    if vim.bo[bufnr].modified then
      return vim.notify(
        "csv-table: " .. full .. " has unsaved changes. Write or discard them first.",
        vim.log.levels.ERROR
      )
    end

    -- `bufadd` leaves a buffer off the buffer list, where `:ls`, `:bnext` and every
    -- picker that reads the list would miss it.
    vim.bo[bufnr].buflisted = true

    -- nvim runs every read command that matches, so capturing a name the extension
    -- pattern already takes would read the file twice.
    if not autocmds.is_captured_by_extension(full) then
      autocmds.capture(bufnr)
    end

    -- Loading an unloaded buffer fires the read command on its own. A buffer that
    -- already holds the file, as text or as a table from an older read, is loaded
    -- and takes an `:edit` to read again.
    local loaded = vim.api.nvim_buf_is_loaded(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    if loaded then
      vim.cmd.edit()
    end
  end, {
    nargs = "?",
    complete = function(lead)
      local matches = vim.fn.getcompletion(lead, "file")
      if DISABLE:find(lead, 1, true) == 1 then
        table.insert(matches, 1, DISABLE)
      end
      return matches
    end,
    desc = "Open a file as a table, or " .. DISABLE .. " to read it as text again",
  })
end

return M
