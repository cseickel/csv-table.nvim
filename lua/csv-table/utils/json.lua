--[[
Breaks a cell holding JSON onto one value per line.

The text is walked rather than decoded and printed again, so only the whitespace
between tokens changes. Every number, key order and escape is the one in the file.
]]

local M = {}

local INDENT = "  "

--- Whether `value` is a JSON object or array. A bare number or word parses as
--- JSON too, and indenting one would help nobody.
---@param value string
---@return boolean
function M.is_json(value)
  local first_character = value:match("^%s*(.)")
  if first_character ~= "{" and first_character ~= "[" then
    return false
  end
  return (pcall(vim.json.decode, value))
end

--- One value per line, nested values indented. An empty object or array stays on
--- the line it started, since there is nothing to put underneath it.
---@param value string
---@return string[]
function M.indent(value)
  local lines = {}
  local line_parts = {}
  local depth = 0
  local in_string = false
  local escaped = false

  local function push(text)
    line_parts[#line_parts + 1] = text
  end

  local function newline()
    lines[#lines + 1] = table.concat(line_parts)
    line_parts = { string.rep(INDENT, depth) }
  end

  local index = 1
  while index <= #value do
    local character = value:sub(index, index)

    if in_string then
      push(character)
      if escaped then
        escaped = false
      elseif character == "\\" then
        escaped = true
      elseif character == '"' then
        in_string = false
      end
    elseif character == '"' then
      in_string = true
      push(character)
    elseif character == "{" or character == "[" then
      local closer = character == "{" and "}" or "]"
      local next_at = value:find("%S", index + 1)
      if next_at and value:sub(next_at, next_at) == closer then
        push(character .. closer)
        index = next_at
      else
        push(character)
        depth = depth + 1
        newline()
      end
    elseif character == "}" or character == "]" then
      depth = math.max(depth - 1, 0)
      newline()
      push(character)
    elseif character == "," then
      push(character)
      newline()
    elseif character == ":" then
      push(": ")
    elseif not character:match("%s") then
      push(character)
    end

    index = index + 1
  end

  lines[#lines + 1] = table.concat(line_parts)
  return lines
end

return M
