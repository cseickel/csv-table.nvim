--[[
Defines `csv.Reader`, one per buffer, which runs xan and decodes what comes
back.

- `page` draws the table the state asks for, parsed and ready for the buffer
- `count`, `row`, `yank`, `frequency` and `stats` each answer one question
- `report` is how every failure reaches the user

A reader runs one xan at a time. Starting another drops the callbacks of the one
before it and kills it, so the answer the user is waiting on is the only one
still being worked out and a run that lost its place reaches nobody.

This is the way in to the rest of the folder. `commands`, `pipeline`,
`expression` and `parse` beside it write the argv and the moonblade xan takes and
read what it prints, and no module outside these five names xan.
]]

local columns = require("csv-table.columns")
local commands = require("csv-table.reader.commands")
local parse = require("csv-table.reader.parse")
local view_state = require("csv-table.state")

local M = {}

local SIGTERM = 15

---@class csv.Frequency
---@field value string
---@field count integer

---@class csv.Reader
---@field handle vim.SystemObj|nil The xan running now.
---@field pending { on_error: fun(message: string), on_output: fun(stdout: string) }|nil
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

--- Run `argv`, handing stdout to `on_output` or the message to `on_error`.
---
--- `xan run` exits 0 even when a stage inside the pipeline fails, and runs the
--- stages after it with no input, so anything on stderr is a failure whatever
--- the exit code says.
---@param argv string[]
---@param on_error fun(message: string)
---@param on_output fun(stdout: string)
function Reader:run(argv, on_error, on_output)
  self:cancel()

  local pending = { on_error = on_error, on_output = on_output }
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
      return pending.on_error(message)
    end
    if result.code ~= 0 then
      return pending.on_error(argv[1] .. " exited " .. result.code)
    end
    pending.on_output(result.stdout)
  end))
end

--- Run `argv` and decode its output as one JSON object per line.
---@param argv string[]
---@param on_error fun(message: string)
---@param on_rows fun(rows: table[])
function Reader:run_json_lines(argv, on_error, on_rows)
  self:run(argv, on_error, function(stdout)
    local rows = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local decoded, row = pcall(vim.json.decode, line)
      if not decoded then
        return on_error("xan returned output that is not JSON")
      end
      table.insert(rows, row)
    end
    on_rows(rows)
  end)
end

--- The page `state` asks for, drawn by xan and parsed into a layout.
---
--- The columns and the first row number are read once here, so the command and
--- the layout describe the same page however the state moves on afterwards.
---@param state csv.State
---@param on_error fun(message: string)
---@param on_page fun(layout: csv.Layout)
function Reader:page(state, on_error, on_page)
  local display_columns = columns.display_columns(state)
  local first_row_number = view_state.first_row_number(state)

  self:run(commands.render(state, display_columns), on_error, function(stdout)
    local lines = vim.split(stdout, "\n", { plain = true })
    local layout, err = parse.page(lines, display_columns, first_row_number)
    if not layout then
      return on_error(err)
    end

    -- The file has just been read, so whatever was read from it before is old.
    self.row = nil
    on_page(layout)
  end)
end

--- How many rows the current filters leave.
---@param state csv.State
---@param on_error fun(message: string)
---@param on_count fun(count: integer)
function Reader:count(state, on_error, on_count)
  self:run(commands.count(state), on_error, function(stdout)
    local count = tonumber(vim.trim(stdout))
    if not count then
      return on_error("xan count returned " .. vim.trim(stdout))
    end
    on_count(count)
  end)
end

-- What `fmt --ascii` writes between two values and at the end of a record.
local UNIT_SEPARATOR = "\31"
local RECORD_SEPARATOR = "\30"

--- Every value of one row of the source, in file order, so the column with id 0
--- holds the first of them. Each value is what the file holds rather than what
--- the table draws.
---
--- The row read last is kept, so reading cell after cell along one row runs xan
--- once. `page` drops it, since that is the file being read again.
---
--- Nothing is escaped on the way here, so a value holding a separator of its own
--- would split into two. The two separators are control characters, which is
--- what makes that worth trading for values that arrive as they are written.
---@param state csv.State
---@param row_id integer
---@param on_error fun(message: string)
---@param on_values fun(values: string[])
function Reader:row_values(state, row_id, on_error, on_values)
  if self.row and self.row.row_id == row_id then
    return on_values(self.row.values)
  end

  self:run(commands.row(state, row_id), on_error, function(stdout)
    if stdout == "" then
      return on_error("row " .. row_id .. " is no longer in the file")
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

--- Rows written in `opts.format`, in the order they are drawn. Every writer ends
--- its output with a newline, which a spreadsheet would paste as an empty row.
---@param state csv.State
---@param opts { rowids: integer[], columns: csv.Column[], headers: boolean, format: string }
---@param on_error fun(message: string)
---@param on_text fun(text: string)
function Reader:yank(state, opts, on_error, on_text)
  self:run(commands.yank(state, opts), on_error, function(stdout)
    on_text((stdout:gsub("\n$", "")))
  end)
end

--- Every value `column` holds and how many rows hold it, most frequent first.
---@param state csv.State
---@param column csv.Column
---@param on_error fun(message: string)
---@param on_values fun(values: csv.Frequency[])
function Reader:frequency(state, column, on_error, on_values)
  self:run_json_lines(commands.frequency(state, column), on_error, function(rows)
    local values = {}
    for index, row in ipairs(rows) do
      values[index] = { value = row.value, count = tonumber(row.count) or 0 }
    end
    on_values(values)
  end)
end

--- What xan computes about the rows on display, one row per column, or for
--- `column` alone.
---@param state csv.State
---@param column csv.Column|nil
---@param on_error fun(message: string)
---@param on_stats fun(rows: table<string, string>[])
function Reader:stats(state, column, on_error, on_stats)
  self:run_json_lines(commands.stats(state, column), on_error, function(rows)
    if #rows == 0 then
      return on_error("xan stats returned nothing")
    end
    on_stats(rows)
  end)
end

return M
