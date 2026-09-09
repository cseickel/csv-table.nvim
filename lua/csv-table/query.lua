--[[
Runs xan and decodes what comes back.

- `run` spawns an argv and hands stdout to a callback
- `run_json_lines` decodes one JSON object per line
- `count`, `row`, `yank`, `frequency` and `stats` each run one command and
  return the value it asked for
- `report` is how every failure reaches the user
]]

local commands = require("csv-table.commands")

local M = {}

---@class csv.Frequency
---@field value string
---@field count integer

--- How every failure reaches the user.
---@param message string
function M.report(message)
  vim.notify("csv-table: " .. message, vim.log.levels.ERROR)
end

--- Run `argv`, handing stdout to `on_output` or the message to `on_error`.
---
--- `xan run` exits 0 even when a stage inside the pipeline fails, and runs the
--- stages after it with no input, so anything on stderr is a failure whatever
--- the exit code says.
---@param argv string[]
---@param on_error fun(message: string)
---@param on_output fun(stdout: string)
function M.run(argv, on_error, on_output)
  vim.system(argv, { text = true }, vim.schedule_wrap(function(result)
    local message = vim.trim(result.stderr or "")
    if message ~= "" then
      return on_error(message)
    end
    if result.code ~= 0 then
      return on_error(argv[1] .. " exited " .. result.code)
    end
    on_output(result.stdout)
  end))
end

--- Run `argv` and decode its output as one JSON object per line.
---@param argv string[]
---@param on_error fun(message: string)
---@param on_rows fun(rows: table[])
function M.run_json_lines(argv, on_error, on_rows)
  M.run(argv, on_error, function(stdout)
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

--- How many rows the current filters leave.
---@param state csv.State
---@param on_error fun(message: string)
---@param on_count fun(count: integer)
function M.count(state, on_error, on_count)
  M.run(commands.count(state), on_error, function(stdout)
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
--- Nothing is escaped on the way here, so a value holding a separator of its own
--- would split into two. The two separators are control characters, which is
--- what makes that worth trading for values that arrive as they are written.
---@param state csv.State
---@param rowid integer
---@param on_error fun(message: string)
---@param on_values fun(values: string[])
function M.row(state, rowid, on_error, on_values)
  M.run(commands.row(state, rowid), on_error, function(stdout)
    if stdout == "" then
      return on_error("row " .. rowid .. " is no longer in the file")
    end

    local record = (stdout:gsub(RECORD_SEPARATOR .. "$", ""))
    local values = vim.split(record, UNIT_SEPARATOR, { plain = true })
    -- The last value is the padding column `csv-table.commands` appends, which
    -- belongs to no column of the file.
    table.remove(values)
    on_values(values)
  end)
end

--- Rows written in `opts.format`, in the order they are drawn. Every writer ends
--- its output with a newline, which a spreadsheet would paste as an empty row.
---@param state csv.State
---@param opts { rowids: integer[], columns: csv.Column[], headers: boolean, format: string }
---@param on_error fun(message: string)
---@param on_text fun(text: string)
function M.yank(state, opts, on_error, on_text)
  M.run(commands.yank(state, opts), on_error, function(stdout)
    on_text((stdout:gsub("\n$", "")))
  end)
end

--- Every value `column` holds and how many rows hold it, most frequent first.
---@param state csv.State
---@param column csv.Column
---@param on_error fun(message: string)
---@param on_values fun(values: csv.Frequency[])
function M.frequency(state, column, on_error, on_values)
  M.run_json_lines(commands.frequency(state, column), on_error, function(rows)
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
function M.stats(state, column, on_error, on_stats)
  M.run_json_lines(commands.stats(state, column), on_error, function(rows)
    if #rows == 0 then
      return on_error("xan stats returned nothing")
    end
    on_stats(rows)
  end)
end

return M
