--[[
Builds every argv the plugin runs. All of them are `xan`, and all but `sheets`
are `xan run '<stages>' <path>`, one process with no shell and no pipes.

A source that is not already CSV takes a `from` stage in front, so every stage
below it sees CSV whatever the file on disk holds.
]]

local expression = require("csv-table.reader.expression")
local pipeline = require("csv-table.reader.pipeline")

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

--- The stage that turns a source into CSV, absent when it already is one. `xan
--- from` infers the format from the extension, so it is never named.
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

--- The argv running `stages` against `path`, reading it as CSV first if it is not
--- already CSV.
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

---@param query csv.Query
---@param stages string
---@return string[]
local function run_query(query, stages)
  return run(query.file.path, query.file.sheet, stages)
end

--- The argv drawing the page `query` asks for.
---@param query csv.Query
---@param display_columns csv.Column[] The columns to draw, in display order.
---@return string[]
function M.render(query, display_columns)
  return run_query(query, pipeline.build(query, display_columns))
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

--- The argv for the sample `csv-table.file.format` measures precision from.
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

--- The stage that keeps every record at least two values wide. A record holding
--- one empty value would be written as an empty line, so the writer quotes it and
--- the value arrives as `""`. `csv-table.reader` drops this column as it splits
--- the record.
local PADDING = "map " .. pipeline.quote('("") as csv_table_padding')

--- The argv reading one whole row, the ASCII unit separator between its values
--- and the record separator at the end. `--quote-never` writes each value as the
--- file holds it, so a comma, a quote or a newline inside a value arrives whole
--- and nothing has to be unescaped.
---
--- `enum` numbers rows by their position in the source before anything filters or
--- sorts them, so a row id is the number of rows to skip.
---@param query csv.Query
---@param row_id integer
---@return string[]
function M.row(query, row_id)
  return run_query(query, table.concat({
    string.format("slice -s %d -l 1", row_id),
    PADDING,
    "behead",
    "fmt --ascii --quote-never",
  }, " | "))
end

--- The name `map` gives the column the sort orders on. It is never addressed by
--- name, so a source column sharing it does no harm.
local ORDER_COLUMN = "csv_table_order"

--- Whether `row_ids` is a run of consecutive rows already in file order, which is
--- what an unsorted page leaves.
---@param row_ids integer[]
---@return boolean
local function consecutive(row_ids)
  for index = 2, #row_ids do
    if row_ids[index] ~= row_ids[index - 1] + 1 then
      return false
    end
  end
  return true
end

--- The stages that put the rows back in the order they are drawn in. `slice -I`
--- returns them in file order whatever order it was asked in, so every row looks
--- its own id up in a map of row id to screen position and the sort reads that.
---@param row_ids integer[]
---@param kept integer How many columns the export keeps.
---@return string[]
local function ordering_stages(row_ids, kept)
  local positions = {}
  for position, row_id in ipairs(row_ids) do
    positions[position] = string.format('"%d": %d', row_id, position)
  end

  local order = string.format(
    "get({%s}, col(0)) as %s",
    table.concat(positions, ", "),
    ORDER_COLUMN
  )
  return {
    "map " .. pipeline.quote(order),
    -- The row id sits at 0 and the kept columns run to `kept`, so `map` appends
    -- this one just past them.
    string.format("sort -s %d -N", kept + 1),
  }
end

--- The stage that writes each format, keyed by the name the export actions use.
--- Every stage above emits CSV, so `csv` adds no stage of its own.
local WRITERS = {
  tsv = "fmt --tabs",
  csv = nil,
  json = "to json",
  markdown = "to md",
}

--- The stage that drops the row id and leaves the exported columns.
---
--- `to json` keys each object by header name and `to md` heads each column with
--- it, and a file may repeat a header, so those two take the labels instead:
--- unique, and what the user reads in the drawn header.
---@param block csv.Block
---@param format string
---@return string
local function keeping_stage(block, format)
  local kept = {}
  local named = format == "json" or format == "markdown"

  for index, column in ipairs(block.columns) do
    -- The row id leads the stream, so the first exported column sits at 1.
    if named then
      kept[index] = string.format("col(%d) as %s", index, expression.string_literal(column.label))
    else
      kept[index] = index
    end
  end

  if named then
    return "select -e " .. pipeline.quote(table.concat(kept, ", "))
  end
  return "select " .. pipeline.quote(table.concat(kept, ","))
end

--- The argv writing the block. Naming the rows by id is what keeps the filter and
--- the sort from running again: they decided which rows are on screen, and the
--- ids say which of those to read.
---@param query csv.Query
---@param export csv.Export
---@return string[]
function M.export(query, export)
  local block = export.block
  local ids = {}
  for index, column in ipairs(block.columns) do
    ids[index] = column.column_id
  end

  local stages = {
    "select " .. pipeline.quote(table.concat(ids, ",")),
    "enum -c " .. pipeline.quote(query.file.rowid_column.name),
  }

  if consecutive(block.row_ids) then
    table.insert(stages, string.format("slice -s %d -l %d", block.row_ids[1], #block.row_ids))
  else
    table.insert(stages, "slice -I " .. table.concat(block.row_ids, ","))
    for _, stage in ipairs(ordering_stages(block.row_ids, #block.columns)) do
      table.insert(stages, stage)
    end
  end

  table.insert(stages, keeping_stage(block, export.format))
  if not export.headers then
    table.insert(stages, "behead")
  end
  if WRITERS[export.format] then
    table.insert(stages, WRITERS[export.format])
  end
  return run_query(query, table.concat(stages, " | "))
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
---@param query csv.Query
---@param wanted csv.Column[]
---@param stage fun(positions: table<integer, integer>): string
---@return string[]
local function narrowed_argv(query, wanted, stage)
  local stages, positions = pipeline.narrowing_stages(query, wanted)
  table.insert(stages, stage(positions))
  return run_query(query, table.concat(stages, " | "))
end

--- The argv counting the rows the current filters leave.
---@param query csv.Query
---@return string[]
function M.count(query)
  return narrowed_argv(query, {}, function()
    return "count"
  end)
end

--- The argv listing the distinct values of `column` among the rows the current
--- filters leave, as one JSON object per value, most frequent first.
---@param query csv.Query
---@param column csv.Column
---@return string[]
function M.frequency(query, column)
  return narrowed_argv(query, { column }, function(positions)
    return "frequency -s " .. positions[column.column_id] .. " -A | to jsonl --strings '*'"
  end)
end

--- The argv summarizing the rows the current filters leave, one JSON object per
--- column, or per every column when `column` is absent.
---@param query csv.Query
---@param column csv.Column|nil
---@return string[]
function M.stats(query, column)
  local wanted = column and { column } or query.file.columns
  return narrowed_argv(query, wanted, function(positions)
    local stage = "stats -A"
    if column then
      stage = stage .. " -s " .. positions[column.column_id]
    end
    return stage .. " | to jsonl --strings '*'"
  end)
end

return M
