--[[
The test vocabulary: `describe`, `it` and the checks.

A spec file returns nothing and calls `describe` at the top level. `run.lua`
loads each one, then reports what failed and exits nonzero when anything did.
]]

local M = {}

local results = { passed = 0, failures = {} }
local context = {}

---@param name string
---@param body fun()
function M.describe(name, body)
  table.insert(context, name)
  body()
  table.remove(context)
end

---@param name string
---@param body fun()
function M.it(name, body)
  table.insert(context, name)
  local ok, err = pcall(body)
  if ok then
    results.passed = results.passed + 1
  else
    table.insert(results.failures, {
      name = table.concat(context, " "),
      message = tostring(err),
    })
  end
  table.remove(context)
end

---@param value any
---@return string
local function shown(value)
  if type(value) == "table" then
    local parts = {}
    for _, item in ipairs(value) do
      table.insert(parts, shown(item))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(value)
end

---@param actual any
---@param expected any
function M.equals(actual, expected)
  if actual ~= expected then
    error(string.format("expected %s, got %s", shown(expected), shown(actual)), 2)
  end
end

---@param value any
function M.truthy(value)
  if not value then
    error("expected a value, got " .. shown(value), 2)
  end
end

--- Assert that `text` holds `pattern`, which is a lua pattern.
---@param text string
---@param pattern string
function M.matches(text, pattern)
  if not text:find(pattern) then
    error(string.format("expected a match for %s in\n  %s", pattern, text), 2)
  end
end

--- Assert that `text` is free of `pattern`, which is how a spec says a stage
--- left something out.
---@param text string
---@param pattern string
function M.lacks(text, pattern)
  if text:find(pattern) then
    error(string.format("expected no match for %s in\n  %s", pattern, text), 2)
  end
end

---@return integer passed
---@return { name: string, message: string }[] failures
function M.results()
  return results.passed, results.failures
end

return M
