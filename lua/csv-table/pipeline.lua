--[[
Builds the argument for `xan run '<pipeline>' <file>`, the one process that
draws a page.

- `carried_columns` picks the columns the run takes, and where each one sits
- `narrowing_stages` is select, enum and filter, which `count`, `stats` and
  `frequency` open with as well
- `build` adds sort, slice, the formatting `select -e`, and `view`
- `quote` wraps one argument for the shlex splitting xan does

The opening `select | enum` fixes the shape: the row id at 0 and each carried
column at its place in the list, so every stage below names a column by that
number. Pure Lua, so it runs without nvim.
]]

local columns = require("csv-table.columns")
local expression = require("csv-table.expression")

-- Taken off the module as a bare function, since `format` here names a column's
-- format.
local is_numeric = require("csv-table.format").is_numeric

local M = {}

--- Quote one argument of the pipeline string, which xan splits with shlex.
---@param value string
---@return string
function M.quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local shell_quote = M.quote

--- The columns the run carries, and where each one sits once the row id is
--- prepended. `wanted` leads, and any column a sort key or a filter names joins
--- the end, so the expressions have something to address.
---@param state csv.State
---@param wanted csv.Column[]
---@return csv.Column[] carried
---@return table<integer, integer> position_by_column_id
function M.carried_columns(state, wanted)
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
  for _, key in ipairs(state.sort_keys) do
    add(key.column)
  end
  for _, filter in ipairs(state.filters) do
    add(filter.column)
  end

  local positions = {}
  for index, column in ipairs(carried) do
    positions[column.column_id] = index
  end
  return carried, positions
end

--- The two stages that fix the shape: take the carried columns out of the file
--- by their file positions, then prepend the row id, which is the row's position
--- in the file and survives every filter and sort below.
---@param state csv.State
---@param carried csv.Column[]
---@return string[]
local function opening_stages(state, carried)
  local ids = {}
  for index, column in ipairs(carried) do
    ids[index] = column.column_id
  end

  local stages = {}
  -- `count` over an unfiltered file carries nothing, and `select` wants at
  -- least one column.
  if #ids > 0 then
    table.insert(stages, "select " .. shell_quote(table.concat(ids, ",")))
  end
  table.insert(stages, "enum -c " .. shell_quote(state.rowid_column.name))
  return stages
end

--- Sort stages, least significant key first.
--- `xan sort` applies one direction to all its keys and is stable, so a
--- multi-key sort with mixed directions is one stage per key, applied in
--- reverse order of significance.
---@param state csv.State
---@param positions table<integer, integer>
---@return string[]
local function sort_stages(state, positions)
  local order = state.sort_keys
  local stages = {}
  for i = #order, 1, -1 do
    local key = order[i]
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
---@param state csv.State
---@param column csv.Column
---@return string
local function header_text(state, column)
  local text = column.label
  for position, key in ipairs(state.sort_keys) do
    if key.column.column_id == column.column_id then
      text = text .. " " .. (key.direction == "asc" and ASCENDING or DESCENDING)
      if #state.sort_keys > 1 then
        text = text .. position
      end
    end
  end

  local format = state.formats[column.column_id]
  if format and format.align and columns.text_length(text) > format.width then
    text = columns.truncate(text, format.width)
  end
  return text
end

--- The closing stage: the row id, then every displayed column formatted and
--- given its header text. Each clause falls through, so a value that fails to
--- cast lands on its raw text, and every value ends in a space, because `xan
--- view` renders an empty cell as the text `<empty>`.
---@param state csv.State
---@param display_columns csv.Column[]
---@param positions table<integer, integer>
---@return string
local function display_stage(state, display_columns, positions)
  local clauses = {
    string.format("col(0) as %s", columns.string_literal(state.rowid_column.name)),
  }

  for _, column in ipairs(display_columns) do
    local header = columns.string_literal(header_text(state, column))
    local reference = string.format("col(%d)", positions[column.column_id])
    local format = state.formats[column.column_id]
    local expr = format and expression.value_expression(reference, format) or reference

    if expr == reference then
      table.insert(clauses, string.format('%s || " " as %s', reference, header))
    else
      table.insert(clauses, string.format('try(%s) || %s || " " as %s', expr, reference, header))
    end
  end

  return "select -e " .. shell_quote(table.concat(clauses, ", "))
end

--- The columns `view` should right-align, by their position in the stream it
--- reads. A numeric column needs this because `printf` leaves it a string, which
--- `view` left-aligns. A column the user aligned is padded by `printf` already,
--- so `view` leaves it be.
---@param state csv.State
---@param display_columns csv.Column[]
---@return string|nil
local function right_aligned(state, display_columns)
  local positions = {}
  for index, column in ipairs(display_columns) do
    local format = state.formats[column.column_id]
    if is_numeric(format) and not format.align then
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

--- The stages that leave exactly the rows the filters allow. `count`, `stats`
--- and `frequency` open with these, so they report on the rows the buffer is
--- showing.
---@param state csv.State
---@param wanted csv.Column[] Columns the caller needs to address afterwards.
---@return string[] stages
---@return table<integer, integer> position_by_column_id
function M.narrowing_stages(state, wanted)
  local carried, positions = M.carried_columns(state, wanted)
  local stages = opening_stages(state, carried)
  if #state.filters > 0 then
    table.insert(stages, "filter " .. shell_quote(expression.all_filters(state, positions)))
  end
  return stages, positions
end

--- Build the argument for `xan run`.
---@param state csv.State
---@param display_columns csv.Column[] The columns to draw, in display order.
---@return string
function M.build(state, display_columns)
  local stages, positions = M.narrowing_stages(state, display_columns)

  for _, stage in ipairs(sort_stages(state, positions)) do
    table.insert(stages, stage)
  end

  table.insert(stages, string.format("slice -s %d -l %d", state.page * state.limit, state.limit))
  table.insert(stages, display_stage(state, display_columns, positions))

  -- `-M` hides the meta info
  -- `-e` draws every column at the width its content already has
  -- `-A` shows all rows instead of the 100 row default
  -- `-t table` is named, since `XAN_VIEW_ARGS` can change the default theme and
  -- the syntax file is written for this one
  local view = "view --color never -M -I --repeat-headers never -e -A -t table"
  local aligned = right_aligned(state, display_columns)
  if aligned then
    view = view .. " -r " .. shell_quote(aligned)
  end
  table.insert(stages, view)

  return table.concat(stages, " | ")
end

return M
