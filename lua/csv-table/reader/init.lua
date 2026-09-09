--[[
Defines `csv.Reader`, one per buffer, which runs xan and decodes what comes back.

A reader runs one xan at a time. Starting another drops the callbacks of the one
before it and kills it, so the answer the user is waiting on is the only one
still being worked out and a run that lost its place reaches nobody.

This is the way in to the rest of the folder. `commands`, `pipeline`,
`expression` and `parse` beside it write the argv and the moonblade xan takes and
read what it prints, and no module outside these five names xan.
]]

local commands = require("csv-table.reader.commands")
local file = require("csv-table.file")
local parse = require("csv-table.reader.parse")

local M = {}

local SIGTERM = 15

-- What `fmt --ascii` writes between two values and at the end of a record.
local UNIT_SEPARATOR = "\31"
local RECORD_SEPARATOR = "\30"

---@class csv.Frequency
---@field value string
---@field count integer

---@class csv.Block
---@field row_ids integer[] In the order the rows are drawn.
---@field columns csv.Column[] In the order they are drawn.

---@class csv.Export
---@field block csv.Block
---@field format "tsv"|"csv"|"json"|"markdown"
---@field headers boolean Whether to put the column names above the cells.

---@class csv.Reader
---@field handle vim.SystemObj|nil The xan running now.
---@field pending { on_output: fun(stdout: string) }|nil
---@field row { row_id: integer, values: string[] }|nil The last row read whole.
local Reader = {}
Reader.__index = Reader

--- A reader for one buffer.
---@return csv.Reader
function M.new()
  return setmetatable({ handle = nil, pending = nil, row = nil }, Reader)
end

--- How every failure reaches the user.
---@param message string
function M.report(message)
  vim.notify("csv-table: " .. message, vim.log.levels.ERROR)
end

--- Drop the callbacks of the run in flight and kill it.
function Reader:cancel()
  self.pending = nil
  if self.handle then
    self.handle:kill(SIGTERM)
    self.handle = nil
  end
end

--- Run `argv` and hand its stdout to `on_output`.
---
--- `xan run` exits 0 even when a stage inside the pipeline fails, and runs the
--- stages after it with no input, so anything on stderr is a failure whatever the
--- exit code says.
---@param argv string[]
---@param on_output fun(stdout: string)
function Reader:run(argv, on_output)
  self:cancel()

  local pending = { on_output = on_output }
  self.pending = pending

  self.handle = vim.system(argv, { text = true }, vim.schedule_wrap(function(result)
    -- Another run took the reader while this one was out, which is what says
    -- nobody is waiting on it any more.
    if self.pending ~= pending then
      return
    end
    self.pending, self.handle = nil, nil

    local message = vim.trim(result.stderr or "")
    if message ~= "" then
      return M.report(message)
    end
    if result.code ~= 0 then
      return M.report(argv[1] .. " exited " .. result.code)
    end
    pending.on_output(result.stdout)
  end))
end

--- Run `argv` and decode its output as one JSON object per line.
---@param argv string[]
---@param on_rows fun(rows: table[])
function Reader:run_json_lines(argv, on_rows)
  self:run(argv, function(stdout)
    local rows = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local decoded, row = pcall(vim.json.decode, line)
      if not decoded then
        return M.report("xan returned output that is not JSON")
      end
      table.insert(rows, row)
    end
    on_rows(rows)
  end)
end

--- The page `query` asks for, drawn by xan and parsed.
---
--- The columns and the first row number are read once here, so the command and
--- the page describe the same rows however the query moves on afterwards.
---@param query csv.Query
---@param on_page fun(page: csv.Page)
function Reader:page(query, on_page)
  local display_columns = query:display_columns()
  local first_row_number = query:first_row_number()
  local version = file.version(query.file.path)

  self:run(commands.render(query, display_columns), function(stdout)
    local drawn, err = parse.page(vim.split(stdout, "\n", { plain = true }), {
      columns = display_columns,
      first_row_number = first_row_number,
      file_version = version,
    })
    if not drawn then
      return M.report(err)
    end

    -- The file has just been read, so whatever was read from it before is old.
    self.row = nil
    on_page(drawn)
  end)
end

--- How many rows the query's filters leave.
---@param query csv.Query
---@param on_count fun(count: integer)
function Reader:count(query, on_count)
  self:run(commands.count(query), function(stdout)
    local count = tonumber(vim.trim(stdout))
    if not count then
      return M.report("xan count returned " .. vim.trim(stdout))
    end
    on_count(count)
  end)
end

--- Every value of one row, in file order. The row read last is kept, so reading
--- cell after cell along one row runs xan once, and `page` drops it, since that
--- is the file being read again.
---
--- Nothing is escaped on the way here, so a value holding a separator of its own
--- would split into two. The two separators are control characters, which is what
--- makes that worth trading for values that arrive as they are written.
---@param query csv.Query
---@param row_id integer
---@param on_values fun(values: string[])
local function read_row(self, query, row_id, on_values)
  if self.row and self.row.row_id == row_id then
    return on_values(self.row.values)
  end

  self:run(commands.row(query, row_id), function(stdout)
    if stdout == "" then
      return M.report("row " .. row_id .. " is no longer in the file")
    end

    local record = (stdout:gsub(RECORD_SEPARATOR .. "$", ""))
    local values = vim.split(record, UNIT_SEPARATOR, { plain = true })
    -- The last value is the padding column `csv-table.reader.commands` appends,
    -- which belongs to no column of the file.
    table.remove(values)

    self.row = { row_id = row_id, values = values }
    on_values(values)
  end)
end

--- What one row holds, keyed by column id, as the file holds it rather than as
--- the table draws it.
---@param query csv.Query
---@param row_id integer
---@param on_row fun(row: table<integer, string>)
function Reader:row_values(query, row_id, on_row)
  read_row(self, query, row_id, function(values)
    local by_column = {}
    for index, value in ipairs(values) do
      by_column[index - 1] = value
    end
    on_row(by_column)
  end)
end

--- What one cell holds.
---@param query csv.Query
---@param ref csv.CellRef
---@param on_value fun(value: string)
function Reader:cell(query, ref, on_value)
  read_row(self, query, ref.row_id, function(values)
    on_value(values[ref.column_id + 1] or "")
  end)
end

--- The block written in `export.format`, in the order the rows are drawn. Every
--- writer ends its output with a newline, which a spreadsheet would paste as an
--- empty row.
---@param query csv.Query
---@param export csv.Export
---@param on_text fun(text: string)
function Reader:export(query, export, on_text)
  self:run(commands.export(query, export), function(stdout)
    on_text((stdout:gsub("\n$", "")))
  end)
end

--- Every value `column` holds and how many rows hold it, most frequent first.
---@param query csv.Query
---@param column csv.Column
---@param on_values fun(values: csv.Frequency[])
function Reader:frequency(query, column, on_values)
  self:run_json_lines(commands.frequency(query, column), function(rows)
    local values = {}
    for index, row in ipairs(rows) do
      values[index] = { value = row.value, count = tonumber(row.count) or 0 }
    end
    on_values(values)
  end)
end

--- What xan computes about the rows on display, one row per column, or for
--- `column` alone.
---@param query csv.Query
---@param column csv.Column|nil
---@param on_stats fun(rows: table<string, string>[])
function Reader:stats(query, column, on_stats)
  self:run_json_lines(commands.stats(query, column), function(rows)
    if #rows == 0 then
      return M.report("xan stats returned nothing")
    end
    on_stats(rows)
  end)
end

return M
