--[[
Writes the moonblade expressions xan takes. Filters and formatting reach xan as
expressions rather than flags.

String comparison uses `eq` where numeric comparison uses `==`. A cast that fails
aborts the whole run, so anything that can fail is wrapped in `try`.
]]

local M = {}

local NUMERIC_CONVERSION = "%%[-+ #%d%.]*[diouxXeEfgGaA]"

---@param value string
---@return string
function M.string_literal(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- One filter as an expression. `positions` says where each column sits in the
--- stream the filter reads.
---@param filter csv.Filter
---@param positions table<integer, integer>
---@return string
function M.filter(filter, positions)
  if filter.type == "expr" then
    return "(" .. filter.expression .. ")"
  end

  if filter.type == "rows" then
    local literals = {}
    for index, row_id in ipairs(filter.row_ids) do
      literals[index] = M.string_literal(tostring(row_id))
    end
    return string.format("(col(0) in [%s])", table.concat(literals, ", "))
  end

  local column = string.format("col(%d)", positions[filter.column.column_id])

  -- `try` turns the failed cast of a non-numeric value into a row that does not
  -- satisfy the comparison.
  if filter.type == "numeric" then
    return string.format("try(%s %s %s)", column, filter.operator, filter.value)
  end

  if filter.type == "in" then
    local literals = {}
    for index, value in ipairs(filter.values) do
      literals[index] = M.string_literal(value)
    end
    return string.format("(%s in [%s])", column, table.concat(literals, ", "))
  end

  local value = M.string_literal(filter.value)
  if filter.operator == "eq" or filter.operator == "ne" then
    return string.format("(%s %s %s)", column, filter.operator, value)
  end
  if filter.operator == "regex" then
    return string.format("match(%s, %s)", column, value)
  end
  return string.format("%s(%s, %s)", filter.operator, column, value)
end

--- Every filter in the one expression `xan filter` takes, all of which must hold.
---@param filters csv.Filter[]
---@param positions table<integer, integer>
---@return string
function M.all_filters(filters, positions)
  local parts = {}
  for index, filter in ipairs(filters) do
    parts[index] = M.filter(filter, positions)
  end
  return table.concat(parts, " && ")
end

local PAD_FUNCTION = { left = "rpad", center = "pad", right = "lpad" }

--- The expression writing a column's value in `format`, padding included.
---@param reference string A `col(...)` call naming the column.
---@param format csv.Format
---@return string
function M.value_expression(reference, format)
  local expression = reference

  if format.spec then
    local argument = format.spec:match(NUMERIC_CONVERSION)
        and ("float(" .. reference .. ")")
      or reference
    expression = string.format("printf(%s, %s)", M.string_literal(format.spec), argument)
  elseif format.kind == "float" then
    expression = string.format('printf("%%.%df", float(%s))', format.precision, reference)
  end

  if format.align then
    -- Slicing counts characters where `printf` counts bytes, so the cut never
    -- splits a multi-byte character.
    local width = format.width
    expression = string.format(
      'if(len(%s) > %d, %s[0:%d] ++ "…", %s(%s, %d))',
      expression,
      width,
      expression,
      width - 1,
      PAD_FUNCTION[format.align],
      expression,
      width
    )
  end

  return expression
end

return M
