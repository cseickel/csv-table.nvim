--[[
The actions that move the active cell.

Each one steps by whole cells, so a count moves that many cells rather than
that many characters, and the cursor lands in a cell whichever way it went. The
two that go to an end of the page take a count as a row of the page instead,
the way `G` takes a line number.
]]

local cursor = require("csv-table.cursor")
local utils = require("csv-table.actions.utils")

---@param rows integer
---@param cells integer
---@return fun(buf: csv.Buffer)
local function stepper(rows, cells)
  return function(buf)
    cursor.step(buf, 0, rows * vim.v.count1, cells * vim.v.count1)
  end
end

--- Go to row `count` of the page, or to `edge` of it when no count was given.
---@param edge "first_row"|"last_row"
---@return fun(buf: csv.Buffer)
local function row_goer(edge)
  return function(buf)
    local painted = buf.layout
    if not painted then
      return
    end
    local at = cursor.cell_ref(buf, 0)
    if not at then
      return
    end
    local line = vim.v.count > 0 and painted.first_row + vim.v.count - 1 or painted[edge]
    cursor.move_to(buf, 0, line, at.column + 1)
  end
end

utils.register_action("next_column", "Move to the next column", stepper(0, 1))
utils.register_action("prev_column", "Move to the previous column", stepper(0, -1))
utils.register_action("next_row", "Move down a row", stepper(1, 0))
utils.register_action("prev_row", "Move up a row", stepper(-1, 0))

utils.register_action("first_column", "Move to the first column", stepper(0, -utils.EDGE))
utils.register_action("last_column", "Move to the last column", stepper(0, utils.EDGE))
utils.register_action("first_row", "Move to the top of the page, or to row N", row_goer("first_row"))
utils.register_action("last_row", "Move to the bottom of the page, or to row N", row_goer("last_row"))
