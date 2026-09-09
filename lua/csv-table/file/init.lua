--[[
Defines `csv.File`, the spreadsheet on disk and what reading its head revealed:
the columns, a format per column, the sheet names, and a row id name none of the
columns already uses.

`empty` is a file nothing has been read from yet. `open` reads one through a
reader and answers with the file it found. Both give a whole File, so nothing
downstream asks whether the read has happened.
]]

local commands = require("csv-table.reader.commands")
local format = require("csv-table.file.format")

local M = {}

---@class csv.Column
---@field name string       Header text exactly as it appears in the file.
---@field label string      The name shown to the user, unique across the file.
---@field column_id integer 0-based position among the file's columns. The row id takes -1.
---@field hidden boolean    True when the user has taken the column off display.

---@class csv.File
---@field path string
---@field sheet integer          0-based sheet read, 0 for a file without sheets.
---@field sheets string[]        Every sheet name, empty for a file without sheets.
---@field columns csv.Column[]   Every column, in file order.
---@field formats table<integer, csv.Format> Keyed by column id.
---@field rowid_column csv.Column The row id the pipeline prepends.
local File = {}
File.__index = File

--- A repeated header takes its occurrence as a suffix, so `a,b,a` labels its
--- columns `a[0]`, `b` and `a[1]`. That gives the user one name per column to
--- read, and gives `to jsonl` one key per column to write.
---@param names string[]
---@return csv.Column[]
function M.columns_from_names(names)
  local totals = {}
  for _, name in ipairs(names) do
    totals[name] = (totals[name] or 0) + 1
  end

  local seen = {}
  local columns = {}
  for index, name in ipairs(names) do
    local nth = seen[name] or 0
    seen[name] = nth + 1
    columns[index] = {
      name = name,
      label = totals[name] > 1 and (name .. "[" .. nth .. "]") or name,
      column_id = index - 1,
      hidden = false,
    }
  end
  return columns
end

--- A row id name free of every header, so a `col("id")` in a hand written filter
--- reads the row id.
---@param names string[]
---@return string
local function prepended_name(names)
  local in_use = {}
  for _, name in ipairs(names) do
    in_use[name] = true
  end

  local candidate = "id"
  while in_use[candidate] do
    candidate = candidate .. "_"
  end
  return candidate
end

--- `column_id` -1 keeps the row id clear of every source column and of
--- `file.formats`.
---@param name string
---@return csv.Column
local function rowid_column(name)
  return { name = name, label = name, column_id = -1, hidden = false }
end

--- The file whose contents are already known, which is what `open` answers with
--- and what a spec builds directly.
---@param fields { path: string, sheet: integer, sheets: string[], columns: csv.Column[], formats: table<integer, csv.Format>, rowid_name: string }
---@return csv.File
function M.new(fields)
  return setmetatable({
    path = fields.path,
    sheet = fields.sheet,
    sheets = fields.sheets,
    columns = fields.columns,
    formats = fields.formats,
    rowid_column = rowid_column(fields.rowid_name),
  }, File)
end

--- A file nothing has been read from. It answers every question a File answers,
--- with no columns and no sheets.
---@param path string
---@return csv.File
function M.empty(path)
  return M.new({
    path = path,
    sheet = 0,
    sheets = {},
    columns = {},
    formats = {},
    rowid_name = "id",
  })
end

--- What `path` looks like on disk, as a value two reads can be compared by. A
--- file written again in the same second keeps its modification time, so the
--- size comes along. A file out of reach has no version, and an empty string
--- never matches a version a read recorded.
---@param path string
---@return string
function M.version(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return ""
  end
  return string.format("%d:%d:%d", stat.size, stat.mtime.sec, stat.mtime.nsec)
end

--- Read `path` through `reader` and answer with the file it found. The sheet
--- names are listed first where the file has any, so the headers and the sample
--- come from the sheet that was asked for.
---@param reader csv.Reader
---@param path string
---@param sheet integer|nil 0-based, defaulting to the first sheet.
---@param on_file fun(file: csv.File)
function M.open(reader, path, sheet, on_file)
  if vim.fn.executable("xan") == 0 then
    return reader.report("xan is not on PATH")
  end
  sheet = sheet or 0

  ---@param stdout string
  ---@return string[]
  local function lines_of(stdout)
    -- A sheet may hold an empty header cell, which xan prints as a blank line
    -- and which is a real column, so blank lines are kept.
    local lines = vim.split(stdout, "\n", { plain = true })
    if lines[#lines] == "" then
      table.remove(lines)
    end
    return lines
  end

  ---@param sheets string[]
  local function open_sheet(sheets)
    reader:run(commands.headers(path, sheet), function(stdout)
      local names = lines_of(stdout)
      if #names == 0 then
        return reader.report("no columns in " .. path)
      end

      local columns = M.columns_from_names(names)
      reader:run_json_lines(commands.sample(path, sheet, #columns), function(sample)
        on_file(M.new({
          path = path,
          sheet = sheet,
          sheets = sheets,
          columns = columns,
          formats = format.analyze(sample, columns),
          rowid_name = prepended_name(names),
        }))
      end)
    end)
  end

  if not commands.has_sheets(path) then
    return open_sheet({})
  end

  reader:run(commands.sheets(path), function(stdout)
    open_sheet(lines_of(stdout))
  end)
end

--- The format of `column`, made plain the first time the user changes a column
--- the sample never saw.
---@param column csv.Column
---@return csv.Format
function File:format_of(column)
  local existing = self.formats[column.column_id]
  if not existing then
    existing = format.plain()
    self.formats[column.column_id] = existing
  end
  return existing
end

---@param column csv.Column
---@return boolean
function File:is_numeric(column)
  return format.is_numeric(self.formats[column.column_id])
end

--- The width the user is working from: the one they asked for, or the column as
--- it is drawn when they have not asked yet. The sample can miss the longest
--- value in the file, and the column is drawn to fit the longest value on the
--- page, so the drawn width is the only honest starting point.
---@param column csv.Column
---@param drawn_width integer
---@return integer
function File:working_width(column, drawn_width)
  local existing = self.formats[column.column_id]
  return existing and existing.width or drawn_width
end

--- Show more or fewer decimals. Asking for decimals on a column that is not a
--- number makes it a float, since that is what the request means.
---@param column csv.Column
---@param delta integer
function File:adjust_precision(column, delta)
  local existing = self:format_of(column)
  existing.precision = math.max(0, math.min(existing.precision + delta, format.MAX_PRECISION))
  existing.kind = existing.precision > 0 and "float" or "int"
end

--- Use a printf specification instead of every other formatting rule. An empty
--- specification returns the column to the detected format.
---@param column csv.Column
---@param spec string
function File:set_spec(column, spec)
  self:format_of(column).spec = spec ~= "" and spec or nil
end

--- Pad every value of a column to `width` characters, cutting the longer ones.
--- Padding needs a side to pad towards, so an alignment the user has not chosen
--- settles to the side the column's kind reads on.
---@param column csv.Column
---@param opts { width: integer, align: "left"|"center"|"right"|nil }
function File:set_padding(column, opts)
  local existing = self:format_of(column)
  existing.width = math.max(1, opts.width)
  existing.align = opts.align or existing.align or format.natural_align(existing)
end

return M
