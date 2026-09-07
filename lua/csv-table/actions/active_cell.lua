--[[
The actions that move the active cell.

Each one steps by whole cells, so a count moves that many cells. The two that go
to an end of the page take a count as a row number instead, the way `G` takes a
line number.
]]

local active_cell = require("csv-table.active_cell")
local layout_module = require("csv-table.layout")
local utils = require("csv-table.actions.utils")

---@param rows integer
---@param cells integer
---@return fun(buf: csv.Buffer)
local function stepper(rows, cells)
  return function(buf)
    active_cell.step(buf, 0, rows * vim.v.count1, cells * vim.v.count1)
  end
end

--- Go to the row numbered `count`, or to `edge` of the page when no count was
--- given. The count is the number drawn in column one rather than a position
--- down the page, so what the user types is what they read. A number belonging
--- to another page clamps to the near end of this one.
---@param edge "first_line"|"last_line"
---@return fun(buf: csv.Buffer)
local function row_jump_action(edge)
  return function(buf)
    local layout = buf.layout
    local cell = layout and active_cell.cell(buf, 0)
    if not cell then
      return
    end

    local first = layout_module.row_at_line(layout, layout.first_line)
    local last = layout_module.row_at_line(layout, layout.last_line)
    local row = edge == "first_line" and first or last
    if vim.v.count > 0 then
      local number = math.min(math.max(vim.v.count, first.row_number), last.row_number)
      row = layout_module.row_by_number(layout, number) or row
    end
    active_cell.move_to(buf, 0, { row = row, column = cell.column })
  end
end

utils.register_action("next_column", "Move to the next column", stepper(0, 1))
utils.register_action("prev_column", "Move to the previous column", stepper(0, -1))
utils.register_action("next_row", "Move down a row", stepper(1, 0))
utils.register_action("prev_row", "Move up a row", stepper(-1, 0))

utils.register_action("first_column", "Move to the first column", stepper(0, -utils.EDGE))
utils.register_action("last_column", "Move to the last column", stepper(0, utils.EDGE))
utils.register_action("first_row", "Move to the top of the page, or to row N", row_jump_action("first_line"))
utils.register_action("last_row", "Move to the bottom of the page, or to row N", row_jump_action("last_line"))
