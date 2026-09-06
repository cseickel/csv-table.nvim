--[[
State to xan pipeline.

`xan run '<pipeline>' <file>` executes a whole pipeline in one process, so the
plugin never builds a chain of piped commands and never goes through a shell.
This module is the pure function from view state to that single pipeline string.
It is the only place that knows xan's command syntax, and it can be exercised
without nvim.

The pipeline always starts with `enum`, so a row keeps its source position
through filtering and sorting. That position is the row id, and it is what every
later command names a row by.

A second `enum` runs after the page slice and numbers the rows the user is
looking at, counting from one at the top of the first page. Those two columns are
drawn ahead of the data, and `csv-table.layout` cuts the row id back out of the
text, so the row number is the first cell anything on screen has.
]]

local columns = require("csv-table.columns")
local expression = require("csv-table.expression")

-- Taken as a bare function because `format` is what this file calls the value
-- it would be checking.
local is_numeric = require("csv-table.format").is_numeric

-- Named apart from the `state` parameter every function here takes.
local view_state = require("csv-table.state")

local M = {}

--- Quote one argument of the pipeline string, which xan splits with shlex.
---@param value string
---@return string
function M.quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local shell_quote = M.quote

--- Sort stages, least significant key first.
--- `xan sort` applies one direction to all its keys and is stable, so a
--- multi-key sort with mixed directions is one stage per key, applied in
--- reverse order of significance.
---@param order csv.SortKey[]
---@return string[]
local function sort_stages(order)
  local stages = {}
  for i = #order, 1, -1 do
    local key = order[i]
    local stage = "sort -s " .. shell_quote(columns.selector(key.column))
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

--- The header text each column is rendered under: its display name, with an
--- arrow appended when the view is sorted by it. A multi-key sort numbers its
--- arrows, so the header says which key is the most significant.
---@param selected csv.Column[]
---@param order csv.SortKey[]
---@return string[]
local function header_names(selected, order)
  local names = columns.display_names(selected)
  for position, key in ipairs(order) do
    for index, column in ipairs(selected) do
      if column.index == key.column.index then
        local arrow = key.direction == "asc" and ASCENDING or DESCENDING
        names[index] = names[index] .. " " .. arrow
        if #order > 1 then
          names[index] = names[index] .. position
        end
      end
    end
  end
  return names
end

--- The `map` stage that gives each column its decimals, padding and alignment.
--- Runs after `rename`, so a column is addressed by its header name, which is
--- unique. Every clause falls through: a value that will not cast lands on its
--- raw text rather than aborting the run, and a value that is empty lands on a
--- space, because `xan view` renders an empty cell as the text `<empty>`.
---@param selected csv.Column[]
---@param headers string[]
---@param formats table<integer, csv.Format>
---@return string
local function format_stage(selected, headers, formats)
  local clauses = {}
  for index, column in ipairs(selected) do
    local literal = columns.string_literal(headers[index])
    local reference = string.format("col(%s)", literal)
    local format = formats[column.index]
    local expr = format and expression.value_expression(reference, format) or reference

    if expr == reference then
      clauses[index] = string.format('%s || " " as %s', reference, literal)
    else
      clauses[index] = string.format('try(%s) || %s || " " as %s', expr, reference, literal)
    end
  end

  return "map -O " .. shell_quote(table.concat(clauses, ", "))
end

--- The header text as the user reads it, which is the machine name cut to the
--- column's width. `view` sizes a column to its widest cell and the header is
--- one of them, so a column cannot be narrower than its own name until the name
--- is cut too.
---@param selected csv.Column[]
---@param headers string[]
---@param formats table<integer, csv.Format>
---@return string[]|nil nil when no header needs cutting.
local function truncated_headers(selected, headers, formats)
  local truncated = {}
  local cut = false
  for index, column in ipairs(selected) do
    local format = formats[column.index]
    truncated[index] = headers[index]
    if format and format.align and columns.text_length(headers[index]) > format.width then
      truncated[index] = columns.truncate(headers[index], format.width)
      cut = true
    end
  end
  return cut and truncated or nil
end

--- Header names of the columns `view` should right-align. A numeric column
--- needs this because `printf` leaves it a string, which `view` left-aligns.
--- A column the user aligned is padded by `printf` already, so `view` must leave
--- it be.
---@param selected csv.Column[]
---@param headers string[]
---@param formats table<integer, csv.Format>
---@return string|nil
local function right_aligned_names(selected, headers, formats)
  local names = {}
  for index, column in ipairs(selected) do
    local format = formats[column.index]
    if is_numeric(format) and not format.align then
      table.insert(names, columns.quote_name(headers[index]))
    end
  end

  if #names == 0 then
    return nil
  end
  return table.concat(names, ",")
end

--- The columns the buffer draws: the row id, then the row number, then the
--- source columns on display. The row id leads because `csv-table.layout` cuts
--- the first cell away, which leaves the row number at the head of every line.
---
--- Neither prepended column has a source position, so both take one no source
--- column can hold and neither finds an entry in `state.formats`.
---@param state csv.State
---@return csv.Column[]
local function selected_columns(state)
  local selected = {
    { name = state.rowid_name, nth = 0, index = -1, duplicated = false },
    { name = state.row_number_name, nth = 0, index = -2, duplicated = false },
  }
  local source = #state.column_order > 0 and state.column_order or state.columns
  for _, column in ipairs(source) do
    table.insert(selected, column)
  end
  return selected
end

--- The stages that narrow the file to the rows on display, without paging,
--- column selection or formatting. Shared with the counting and summarizing
--- commands, so those see exactly the rows the buffer is showing.
---@param state csv.State
---@return string[]
function M.narrowing_stages(state)
  local stages = { "enum -c " .. shell_quote(state.rowid_name) }
  if #state.filters > 0 then
    table.insert(stages, "filter " .. shell_quote(expression.all_filters(state)))
  end
  return stages
end

--- The stages that leave exactly the rows the buffer is showing: the filters,
--- the sort, and the slice that takes the page. Everything after them is
--- presentation.
---@param state csv.State
---@return string[]
local function page_stages(state)
  local stages = M.narrowing_stages(state)

  for _, stage in ipairs(sort_stages(state.sort_keys)) do
    table.insert(stages, stage)
  end

  table.insert(stages, string.format("slice -s %d -l %d", state.page * state.limit, state.limit))
  return stages
end

--- Build the argument for `xan run`.
---@param state csv.State
---@return string
function M.build(state)
  local stages = page_stages(state)

  -- Numbering after the slice counts the rows on the page rather than the rows
  -- the filters left, so the start says which page these are.
  table.insert(stages, string.format(
    "enum -c %s -S %d",
    shell_quote(state.row_number_name),
    view_state.first_row_number(state)
  ))

  local selected = selected_columns(state)
  local headers = header_names(selected, state.sort_keys)
  table.insert(stages, "select " .. shell_quote(columns.selection(selected)))
  table.insert(stages, "rename " .. shell_quote(columns.rename_argument(headers)))

  table.insert(stages, format_stage(selected, headers, state.formats))

  -- `map` addresses each column by header name, so the headers are cut only
  -- after it runs. Two cut headers may well match, and `map` needs them unique.
  local truncated = truncated_headers(selected, headers, state.formats)
  if truncated then
    table.insert(stages, "rename " .. shell_quote(columns.rename_argument(truncated)))
  end

  -- `-M` hides the meta info
  -- `-e` renders every column at full width
  -- `-A` shows all rows instead of the 100 row default
  -- `-t table` is named rather than left to default, since `XAN_VIEW_ARGS` can
  -- change the default theme and the syntax file is written for this one
  local view = "view --color never -M -I --repeat-headers never -e -A -t table"
  local right_aligned = right_aligned_names(selected, headers, state.formats)
  if right_aligned then
    view = view .. " -r " .. shell_quote(right_aligned)
  end
  table.insert(stages, view)

  return table.concat(stages, " | ")
end

return M
