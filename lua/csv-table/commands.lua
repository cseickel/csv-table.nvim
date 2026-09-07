--[[
The argv that runs xan.

`csv-table.pipeline` says which stages a view needs. This module says how to run
them: `xan run '<stages>' <path>`, one process, no shell and no pipes.

A source that is not already CSV gets a `from` stage in front of everything
else, so every other stage sees CSV whatever the file on disk holds.
]]

local columns = require("csv-table.columns")
local pipeline = require("csv-table.pipeline")
local view_state = require("csv-table.state")

local M = {}

--- Formats `xan from` reads that hold more than one table.
local WORKBOOK_FORMATS = { xls = true, xlsx = true, xlsb = true, ods = true }

local SAMPLE_ROWS = 600
-- `sample` reads whatever it is given, so the sample is drawn from the head of
-- the file rather than from all of it.
local SAMPLE_HEAD_ROWS = 60000

---@param path string
---@return string
local function extension(path)
  return (path:match("%.([%w]+)$") or ""):lower()
end

--- Whether `path` names a workbook, which is the only kind of source that has
--- sheets to choose between.
---@param path string
---@return boolean
function M.has_sheets(path)
  return WORKBOOK_FORMATS[extension(path)] == true
end

--- The stage that turns a source into CSV, absent when it already is one.
--- `xan from` infers the format from the extension, so it is never named.
---@param path string
---@param sheet integer|nil 0-based, for a workbook.
---@return string|nil
local function source_stage(path, sheet)
  local suffix = extension(path)
  if suffix == "csv" or suffix == "tsv" then
    return nil
  end
  if M.has_sheets(path) then
    return string.format("from --sheet-index %d", sheet or 0)
  end
  return "from"
end

--- The argv running `stages` against `path`, reading it as CSV first if it is
--- not already CSV.
---@param path string
---@param sheet integer|nil
---@param stages string The pipeline, already joined.
---@return string[]
local function run(path, sheet, stages)
  local from = source_stage(path, sheet)
  if from then
    stages = from .. " | " .. stages
  end
  return { "xan", "run", stages, path }
end

--- The argv for running `state` through xan.
---@param state csv.State
---@param display_columns csv.Column[] The columns to draw, in display order.
---@return string[]
function M.render(state, display_columns)
  return run(state.source, state.sheet, pipeline.build(state, display_columns))
end

--- `to jsonl` keys its object by the column names in the stream, and a CSV may
--- repeat a header, so the columns are renamed to their ids first. The keys come
--- out `"0"`, `"1"`, `"2"`, one per column and free of anything needing quotes.
---@param count integer How many columns the file holds.
---@return string
local function rename_to_ids(count)
  local ids = {}
  for index = 1, count do
    ids[index] = index - 1
  end
  return "rename " .. pipeline.quote(table.concat(ids, ","))
end

--- The argv for the sample `csv-table.format` measures precision from.
---@param path string
---@param sheet integer|nil
---@param column_count integer
---@return string[]
function M.sample(path, sheet, column_count)
  return run(path, sheet, table.concat({
    string.format("slice -l %d", SAMPLE_HEAD_ROWS),
    string.format("sample %d", SAMPLE_ROWS),
    rename_to_ids(column_count),
    "to jsonl --strings '*'",
  }, " | "))
end

--- The argv reading one whole row as a JSON object, keyed by column id.
--- `enum` numbers rows by their position in the source before anything filters
--- or sorts them, so a row id is the number of rows to skip.
---@param state csv.State
---@param rowid integer
---@return string[]
function M.row(state, rowid)
  return run(state.source, state.sheet, table.concat({
    rename_to_ids(#state.columns),
    string.format("slice -s %d -l 1", rowid),
    "to jsonl --strings '*'",
  }, " | "))
end

--- The name `map` gives the column the copy sorts on. It is never addressed by
--- name, so a source column sharing it does no harm.
local ORDER_COLUMN = "csv_table_order"

--- Whether `rowids` is a run of consecutive rows already in file order, which
--- is what an unsorted page leaves.
---@param rowids integer[]
---@return boolean
local function consecutive(rowids)
  for index = 2, #rowids do
    if rowids[index] ~= rowids[index - 1] + 1 then
      return false
    end
  end
  return true
end

--- The stages that put the rows back in the order they are drawn in. `slice -I`
--- returns them in file order whatever order it was asked in, so every row looks
--- its own id up in a map of row id to screen position and the sort reads that.
---@param rowids integer[]
---@param copied integer How many columns the yank keeps.
---@return string[]
local function ordering_stages(rowids, copied)
  local positions = {}
  for position, rowid in ipairs(rowids) do
    positions[position] = string.format('"%d": %d', rowid, position)
  end

  local expression = string.format(
    "get({%s}, col(0)) as %s",
    table.concat(positions, ", "),
    ORDER_COLUMN
  )
  return {
    "map " .. pipeline.quote(expression),
    -- The row id sits at 0 and the copied columns run to `copied`, so `map`
    -- appends this one just past them.
    string.format("sort -s %d -N", copied + 1),
  }
end

--- The stage that writes each format, keyed by the name the yank actions use.
--- Every stage above emits CSV, so `csv` adds no stage of its own.
local WRITERS = {
  tsv = "fmt --tabs",
  csv = nil,
  json = "to json",
  markdown = "to md",
}

--- The stage that drops the row id and leaves the copied columns.
---
--- `to json` keys each object by header name and `to md` heads each column with
--- it, and a file may repeat a header, so those two take the labels instead:
--- unique, and what the user reads in the drawn header.
---@param opts { columns: csv.Column[], format: string }
---@return string
local function keeping_stage(opts)
  local kept = {}
  local named = opts.format == "json" or opts.format == "markdown"

  for index, column in ipairs(opts.columns) do
    -- The row id leads the stream, so the first yanked column sits at 1.
    if named then
      kept[index] = string.format("col(%d) as %s", index, columns.string_literal(column.label))
    else
      kept[index] = index
    end
  end

  if named then
    return "select -e " .. pipeline.quote(table.concat(kept, ", "))
  end
  return "select " .. pipeline.quote(table.concat(kept, ","))
end

--- The argv yanking rows in `opts.format`. Naming the rows by id is what keeps
--- the filter and the sort from running again: they decided which rows are on
--- screen, and the ids say which of those to read.
---@param state csv.State
---@param opts { rowids: integer[], columns: csv.Column[], headers: boolean, format: string } `rowids` in the order the rows are drawn.
---@return string[]
function M.yank(state, opts)
  local ids = {}
  for index, column in ipairs(opts.columns) do
    ids[index] = column.column_id
  end

  local stages = {
    "select " .. pipeline.quote(table.concat(ids, ",")),
    "enum -c " .. pipeline.quote(state.rowid_column.name),
  }

  if consecutive(opts.rowids) then
    table.insert(stages, string.format("slice -s %d -l %d", opts.rowids[1], #opts.rowids))
  else
    table.insert(stages, "slice -I " .. table.concat(opts.rowids, ","))
    for _, stage in ipairs(ordering_stages(opts.rowids, #opts.columns)) do
      table.insert(stages, stage)
    end
  end

  table.insert(stages, keeping_stage(opts))
  if not opts.headers then
    table.insert(stages, "behead")
  end
  if WRITERS[opts.format] then
    table.insert(stages, WRITERS[opts.format])
  end
  return run(state.source, state.sheet, table.concat(stages, " | "))
end

--- The argv that lists a file's column names, one per line.
---@param path string
---@param sheet integer|nil
---@return string[]
function M.headers(path, sheet)
  return run(path, sheet, "headers -j")
end

--- The argv that names every sheet in a workbook, one per line.
---@param path string
---@return string[]
function M.sheets(path)
  return { "xan", "from", "--list-sheets", path }
end

--- Run `stage` over the rows the current filters leave. `wanted` names the
--- columns `stage` addresses, so the opening `select` takes those columns.
---@param state csv.State
---@param wanted csv.Column[]
---@param stage fun(positions: table<integer, integer>): string
---@return string[]
local function narrowed_argv(state, wanted, stage)
  local stages, positions = pipeline.narrowing_stages(state, wanted)
  table.insert(stages, stage(positions))
  return run(state.source, state.sheet, table.concat(stages, " | "))
end

--- The argv counting the rows the current filters leave.
---@param state csv.State
---@return string[]
function M.count(state)
  return narrowed_argv(state, {}, function()
    return "count"
  end)
end

--- The argv listing the distinct values of `column` among the rows the current
--- filters leave, as one JSON object per value, most frequent first.
---@param state csv.State
---@param column csv.Column
---@return string[]
function M.frequency(state, column)
  return narrowed_argv(state, { column }, function(positions)
    local position = positions[column.column_id]
    return "frequency -s " .. position .. " -A | to jsonl --strings '*'"
  end)
end

--- The argv summarizing the rows the current filters leave, one JSON object per
--- column, or per every column when `column` is absent.
---@param state csv.State
---@param column csv.Column|nil
---@return string[]
function M.stats(state, column)
  local wanted = column and { column } or view_state.source_order(state)
  return narrowed_argv(state, wanted, function(positions)
    local stage = "stats -A"
    if column then
      stage = stage .. " -s " .. positions[column.column_id]
    end
    return stage .. " | to jsonl --strings '*'"
  end)
end

return M
