--[[
Builds the argument for `xan run '<pipeline>' <file>`, the one process that draws
a page.

The opening `select | enum` fixes the shape: the row id at 0 and each carried
column at its place in the list, so every stage below names a column by that
number. Pure Lua, so it runs without nvim.
]]

local expression = require("csv-table.reader.expression")
local text = require("csv-table.utils.text")

local M = {}

--- Quote one argument of the pipeline string, which xan splits with shlex.
---@param value string
---@return string
function M.quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

--- The columns the run carries, and where each one sits once the row id is
--- prepended. `wanted` leads, and any column a sort key or a filter names joins
--- the end, so the expressions have something to address.
---@param query csv.Query
---@param wanted csv.Column[]
---@return csv.Column[] carried
---@return table<integer, integer> position_by_column_id
function M.carried_columns(query, wanted)
  local carried, seen = {}, {}
  local function add(column)
    if column and not seen[column.column_id] then
      seen[column.column_id] = true
      table.insert(carried, column)
    end
  end

  for _, column in ipairs(wanted) do
    add(column)
  end
  for _, key in ipairs(query.sort_keys) do
    add(key.column)
  end
  for _, filter in ipairs(query.filters) do
    add(filter.column)
  end

  local positions = {}
  for index, column in ipairs(carried) do
    positions[column.column_id] = index
  end
  return carried, positions
end

--- The two stages that fix the shape: take the carried columns out of the file by
--- their file positions, then prepend the row id, which is the row's position in
--- the file and survives every filter and sort below.
---@param query csv.Query
---@param carried csv.Column[]
---@return string[]
local function opening_stages(query, carried)
  local ids = {}
  for index, column in ipairs(carried) do
    ids[index] = column.column_id
  end

  local stages = {}
  -- `count` over an unfiltered file carries nothing, and `select` wants at least
  -- one column.
  if #ids > 0 then
    table.insert(stages, "select " .. M.quote(table.concat(ids, ",")))
  end
  table.insert(stages, "enum -c " .. M.quote(query.file.rowid_column.name))
  return stages
end

--- Sort stages, least significant key first. `xan sort` applies one direction to
--- all its keys and is stable, so a multi-key sort with mixed directions is one
--- stage per key, applied in reverse order of significance.
---@param query csv.Query
---@param positions table<integer, integer>
---@return string[]
local function sort_stages(query, positions)
  local order = query.sort_keys
  local stages = {}
  for index = #order, 1, -1 do
    local key = order[index]
    local stage = "sort -s " .. positions[key.column.column_id]
    if key.numeric then
      stage = stage .. " -N"
    end
    if key.direction == "desc" then
      stage = stage .. " -R"
    end
    table.insert(stages, stage)
  end
  return stages
end

local ASCENDING = "▲"
local DESCENDING = "▼"

--- The header text a column is drawn under: its label, an arrow when the view is
--- sorted by it, and a cut to the width the user pinned. A multi-key sort numbers
--- its arrows, so the header says which key is the most significant.
---
--- The cut is here because `view` sizes a column to its widest cell and the
--- header is one of the cells, so a long header would widen the column back past
--- the width the values were padded to.
---@param query csv.Query
---@param column csv.Column
---@return string
local function header_text(query, column)
  local header = column.label
  for position, key in ipairs(query.sort_keys) do
    if key.column.column_id == column.column_id then
      header = header .. " " .. (key.direction == "asc" and ASCENDING or DESCENDING)
      if #query.sort_keys > 1 then
        header = header .. position
      end
    end
  end

  local column_format = query.file.formats[column.column_id]
  if column_format and column_format.align and text.length(header) > column_format.width then
    header = text.truncate(header, column_format.width)
  end
  return header
end

--- The closing stage: the row id, then every displayed column formatted and given
--- its header text. Each clause falls through, so a value that fails to cast
--- lands on its raw text, and every value ends in a space, because `xan view`
--- renders an empty cell as the text `<empty>`.
---@param query csv.Query
---@param display_columns csv.Column[]
---@param positions table<integer, integer>
---@return string
local function display_stage(query, display_columns, positions)
  local clauses = {
    string.format("col(0) as %s", expression.string_literal(query.file.rowid_column.name)),
  }

  for _, column in ipairs(display_columns) do
    local header = expression.string_literal(header_text(query, column))
    local reference = string.format("col(%d)", positions[column.column_id])
    local column_format = query.file.formats[column.column_id]
    local expr = column_format and expression.value_expression(reference, column_format) or reference

    if expr == reference then
      table.insert(clauses, string.format('%s || " " as %s', reference, header))
    else
      table.insert(clauses, string.format('try(%s) || %s || " " as %s', expr, reference, header))
    end
  end

  return "select -e " .. M.quote(table.concat(clauses, ", "))
end

--- The columns `view` should right-align, by their position in the stream it
--- reads. A numeric column needs this because `printf` leaves it a string, which
--- `view` left-aligns. A column the user aligned is padded by `printf` already,
--- so `view` leaves it be.
---@param query csv.Query
---@param display_columns csv.Column[]
---@return string|nil
local function right_aligned(query, display_columns)
  local positions = {}
  for index, column in ipairs(display_columns) do
    local column_format = query.file.formats[column.column_id]
    if query:is_numeric(column) and not column_format.align then
      -- The closing `select -e` puts the row id at 0, so the first displayed
      -- column is at 1, which is this loop's own index.
      table.insert(positions, index)
    end
  end

  if #positions == 0 then
    return nil
  end
  return table.concat(positions, ",")
end

--- The stages that leave exactly the rows the filters allow. `count`, `stats` and
--- `frequency` open with these, so they report on the rows the buffer is showing.
---@param query csv.Query
---@param wanted csv.Column[] Columns the caller needs to address afterwards.
---@return string[] stages
---@return table<integer, integer> position_by_column_id
function M.narrowing_stages(query, wanted)
  local carried, positions = M.carried_columns(query, wanted)
  local stages = opening_stages(query, carried)

  local filters = query:effective_filters()
  if #filters > 0 then
    table.insert(stages, "filter " .. M.quote(expression.all_filters(filters, positions)))
  end
  return stages, positions
end

--- The widest a column is drawn when the user has pinned no width. One cell holding
--- a long value would otherwise draw every row of the page at its length.
local WIDEST_COLUMN = 200

--- `xan view -e` draws a column at three quarters of `--cols`, whatever the number
--- of columns.
local COLUMN_SHARE = 0.75

--- What `--cols` has to be for the widest column to be drawn whole. `xan view` sizes
--- columns against a terminal, and this writes to a pipe, so without a number xan
--- takes 80 columns and cuts every column at 60.
---@param query csv.Query
---@param display_columns csv.Column[]
---@return integer
local function view_cols(query, display_columns)
  local widest = WIDEST_COLUMN
  for _, column in ipairs(display_columns) do
    local column_format = query.file.formats[column.column_id]
    if column_format and column_format.width then
      widest = math.max(widest, column_format.width)
    end
  end
  return math.ceil(widest / COLUMN_SHARE)
end

--- Build the argument for `xan run`.
---@param query csv.Query
---@param display_columns csv.Column[] The columns to draw, in display order.
---@return string
function M.build(query, display_columns)
  local stages, positions = M.narrowing_stages(query, display_columns)

  for _, stage in ipairs(sort_stages(query, positions)) do
    table.insert(stages, stage)
  end

  table.insert(
    stages,
    string.format("slice -s %d -l %d", query.page_number * query.limit, query.limit)
  )
  table.insert(stages, display_stage(query, display_columns, positions))

  -- `-M` hides the meta info
  -- `-e` draws every column at the width its content already has
  -- `-A` shows all rows instead of the 100 row default
  -- `--cols` caps how wide one column is drawn, which xan otherwise takes from a
  -- terminal
  -- `-t table` is named, since `XAN_VIEW_ARGS` can change the default theme and
  -- the syntax file is written for this one
  local view = string.format(
    "view --color never -M -I --repeat-headers never -e -A -t table --cols %d",
    view_cols(query, display_columns)
  )
  local aligned = right_aligned(query, display_columns)
  if aligned then
    view = view .. " -r " .. M.quote(aligned)
  end
  table.insert(stages, view)

  return table.concat(stages, " | ")
end

return M
