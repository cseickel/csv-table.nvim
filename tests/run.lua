--[[
Run every spec beside this file.

    lua tests/run.lua

Reads the specs from `tests/`, prints a line per failure, and exits nonzero when
anything failed. It needs the `lua` binary and the repository, so it runs the
same way in a terminal and in CI.
]]

package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;" .. package.path

require("support.nvim")
local test = require("support.test")

_G.describe = test.describe
_G.it = test.it
_G.equals = test.equals
_G.truthy = test.truthy
_G.matches = test.matches
_G.lacks = test.lacks

local SPECS = {
  "columns_spec",
  "layout_spec",
  "pipeline_spec",
  "selection_spec",
}

for _, spec in ipairs(SPECS) do
  require(spec)
end

local passed, failures = test.results()

for _, failure in ipairs(failures) do
  print("FAIL  " .. failure.name)
  print("      " .. failure.message:gsub("\n", "\n      "))
end

print(string.format("%d passed, %d failed", passed, #failures))
os.exit(#failures == 0 and 0 or 1)
