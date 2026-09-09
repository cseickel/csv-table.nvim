--[[
Defines `csv.Source`, what `inspect` learns about a file before anything can be
rendered:

- its columns, from `xan headers`
- a row id name none of those columns already uses
- a `csv.Format` per column, from a sample of rows
- its sheet names, when the file is a workbook

All of it comes from xan, so `inspect` answers a callback.
]]

local columns = require("csv-table.columns")
local commands = require("csv-table.reader.commands")
local format = require("csv-table.format")

local M = {}

---@class csv.Source
---@field path string
---@field columns csv.Column[]
---@field rowid_name string
---@field formats table<string, csv.Format>
---@field sheet integer   0-based index of the sheet read, 0 for a source without sheets.
---@field sheets string[] Every sheet name, empty for a source without sheets.

--- A name for the row id column the pipeline prepends, free of every source
--- header, so a `col("id")` in a hand-written filter reads the row id.
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

--- The lines of `stdout`, blank ones included. A sheet may hold an empty header
--- cell, which xan prints as a blank line and which is a real column, so
--- skipping blank lines would report fewer columns than the sheet has.
---@param stdout string
---@return string[]
local function lines_of(stdout)
  local lines = vim.split(stdout, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

--- Inspect `path` through `reader` and hand back everything needed to build a
--- pipeline for it. The sheet names are listed first where the file has any, so
--- the headers and the sample are read from the sheet that was asked for.
---@param reader csv.Reader
---@param path string
---@param sheet integer|nil 0-based, defaulting to the first sheet.
---@param on_done fun(source: csv.Source)
---@param on_error fun(message: string)
function M.inspect(reader, path, sheet, on_done, on_error)
  if vim.fn.executable("xan") == 0 then
    return on_error("xan is not on PATH")
  end
  sheet = sheet or 0

  ---@param sheets string[]
  local function inspect_sheet(sheets)
    reader:run(commands.headers(path, sheet), on_error, function(stdout)
      local names = lines_of(stdout)
      if #names == 0 then
        return on_error("no columns in " .. path)
      end

      local source_columns = columns.from_names(names)

      local argv = commands.sample(path, sheet, #source_columns)
      reader:run_json_lines(argv, on_error, function(sample)
        on_done({
          path = path,
          columns = source_columns,
          rowid_name = prepended_name(names),
          formats = format.analyze(sample, source_columns),
          sheet = sheet,
          sheets = sheets,
        })
      end)
    end)
  end

  if not commands.has_sheets(path) then
    return inspect_sheet({})
  end

  reader:run(commands.sheets(path), on_error, function(stdout)
    inspect_sheet(lines_of(stdout))
  end)
end

return M
