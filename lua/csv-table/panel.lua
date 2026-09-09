--[[
Opens the panels that describe the plugin and the file.

- `help` searches every action by description and runs the one chosen
- `bindings` pairs each action with the keys that reach it
- `info` gives the source, the row and column counts, the filters, the sort,
  and a line per column
- `stats` gives everything xan reports for one column

`info` and `stats` run through the filters applied, so they describe the rows on
screen rather than the file on disk.
]]

local keymaps = require("csv-table.keymaps")
local picker = require("csv-table.picker")
local reader = require("csv-table.reader")
local view_state = require("csv-table.state")
local window = require("csv-table.window")

local M = {}

local STAT_FIELDS = {
  "type", "count", "count_empty", "cardinality",
  "min", "max", "mean", "median", "stddev", "mode",
}

---@class csv.Key
---@field key string Every key that runs the action, empty for one with no key.
---@field name string Names an action in `csv-table.actions`.
---@field description string

--- Every action, sorted by its description. Sorting by key would put `sa` next
--- to `sd` and `ss`, which do three different things. An action with no key is
--- in the list too, because the help panel runs whatever the user picks.
---@return csv.Key[]
function M.bindings()
  local actions = require("csv-table.actions")

  local keys = {}
  for _, binding in ipairs(keymaps.resolve()) do
    if binding.action then
      keys[binding.action] = keys[binding.action] or {}
      table.insert(keys[binding.action], binding.key)
    end
  end

  local bindings = {}
  for name, action in pairs(actions.get_all_actions()) do
    local bound = keys[name] or {}
    table.sort(bound)
    table.insert(bindings, {
      key = table.concat(bound, " "),
      name = name,
      description = action.description,
    })
  end

  table.sort(bindings, function(left, right)
    return left.description < right.description
  end)
  return bindings
end

--- Search every action and run the one chosen, so a key is something to find
--- rather than something to have memorised, and an action with no key is still
--- one press away.
---@param buf csv.Buffer
function M.help(buf)
  local actions = require("csv-table.actions")
  local bindings = M.bindings()

  local width = 0
  for _, binding in ipairs(bindings) do
    width = math.max(width, #binding.key)
  end

  picker.choose(bindings, {
    prompt = "csv keys",
    format_item = function(binding)
      return string.format("%-" .. width .. "s   %s", binding.key, binding.description)
    end,
  }, function(binding)
    actions.get_action(binding.name).run(buf)
  end)
end

--- How the current filters and sort read as sentences.
---@param buf csv.Buffer
---@return string[]
local function view_lines(buf)
  local lines = {}

  if #buf.state.filters == 0 then
    table.insert(lines, "  no filters")
  end
  for _, filter in ipairs(buf.state.filters) do
    if filter.type == "marked" then
      table.insert(lines, "  marked rows only")
    elseif filter.type == "expr" then
      table.insert(lines, "  " .. filter.expression)
    elseif filter.type == "in" then
      table.insert(lines, string.format(
        "  %s is one of %s",
        filter.column.label,
        table.concat(filter.values, ", ")
      ))
    else
      table.insert(lines, string.format(
        "  %s %s %s",
        filter.column.label,
        filter.operator,
        filter.value
      ))
    end
  end

  table.insert(lines, "")
  if #buf.state.sort_keys == 0 then
    table.insert(lines, "  no sort")
  end
  for position, key in ipairs(buf.state.sort_keys) do
    table.insert(lines, string.format(
      "  %d. %s %s",
      position,
      key.column.label,
      key.direction == "asc" and "ascending" or "descending"
    ))
  end

  return lines
end

--- One line per column: how it is read, how it is shown, and what is in it.
--- The statistics arrive in column order rather than by name, because two
--- columns may share a name and `field` would then describe both.
---@param buf csv.Buffer
---@param stats table<string, string>[] One row per column, row id column first.
---@return string[]
local function column_lines(buf, stats)
  local lines = { string.format(
    "  %-24s %-6s %-4s %-8s %12s %12s %12s %10s",
    "column", "kind", "dec", "align", "min", "max", "mean", "distinct"
  ) }

  ---@param column csv.Column
  ---@param position integer Where the column sits among the rows `stats` returned.
  local function describe(column, position)
    local format = buf.state.formats[column.column_id] or { kind = "text", precision = 0 }
    local summary = stats[position] or {}
    table.insert(lines, string.format(
      "  %-24s %-6s %-4d %-8s %12s %12s %12s %10s",
      column.label,
      format.kind,
      format.precision,
      format.align or "auto",
      summary.min or "",
      summary.max or "",
      summary.mean and summary.mean:sub(1, 12) or "",
      summary.cardinality or ""
    ))
  end

  -- `commands.stats` puts the columns in file order behind the row id, so a
  -- column's row among the results is one past its place in that list.
  for index, column in ipairs(view_state.source_order(buf.state)) do
    describe(column, index + 1)
  end

  return lines
end

--- Describe the file and the view over it.
---@param buf csv.Buffer
function M.info(buf)
  reader.count(buf.state, reader.report, function(count)
    reader.stats(buf.state, nil, reader.report, function(stats)
      local pages = math.max(math.ceil(count / buf.state.limit), 1)
      local lines = {
        "  " .. buf.state.source,
        string.format("  %d rows, %d columns, page %d of %d",
          count, #buf.state.columns, buf.state.page + 1, pages),
        "",
      }
      vim.list_extend(lines, view_lines(buf))
      table.insert(lines, "")
      vim.list_extend(lines, column_lines(buf, stats))

      window.open(lines, { title = "csv info" })
    end)
  end)
end

--- Every statistic xan reports for one column.
---@param buf csv.Buffer
---@param column csv.Column
function M.stats(buf, column)
  reader.stats(buf.state, column, reader.report, function(rows)
    local summary = rows[1]
    local lines = {}
    for _, field in ipairs(STAT_FIELDS) do
      if summary[field] then
        table.insert(lines, string.format("  %-14s %s", field, summary[field]))
      end
    end
    window.open(lines, { title = column.label })
  end)
end

return M
