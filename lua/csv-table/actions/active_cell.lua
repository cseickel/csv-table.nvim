--[[
Registers the actions that move the active cell by whole cells.

A count moves that many cells, so `5l` is five columns and `5G` is the row the
gutter numbers 5. The default map binds only the keys where that count is the
point, since a plain `j` is already a row and the snap in `csv-table.view.movement`
lands it on the right cell.
]]

local utils = require("csv-table.actions.utils")

---@param rows integer
---@param cells integer
---@return fun(view: csv.View)
local function stepper(rows, cells)
  return function(view)
    view:step(rows * vim.v.count1, cells * vim.v.count1)
  end
end

--- Go to the row numbered `count`, or to `edge` of the page when no count was
--- given. The count is the number the gutter shows, so what the user types is what
--- they read. A number belonging to another page clamps to the near end of this one.
---@param edge "first_line"|"last_line"
---@return fun(view: csv.View)
local function row_jump_action(edge)
  return function(view)
    local cell = view:active_cell()
    if not cell then
      return
    end

    local page = view.buffer.page
    local first = page:row_at_line(page.first_line)
    local last = page:row_at_line(page.last_line)
    local row = edge == "first_line" and first or last
    if vim.v.count > 0 then
      local number = math.min(math.max(vim.v.count, first.row_number), last.row_number)
      row = page:row_by_number(number) or row
    end
    view:go_to({ row = row, column = cell.column })
  end
end

utils.register_action("next_column", "Move to the next column", stepper(0, 1))
utils.register_action("prev_column", "Move to the previous column", stepper(0, -1))
utils.register_action("next_row", "Move down a row", stepper(1, 0))
utils.register_action("prev_row", "Move up a row", stepper(-1, 0))

utils.register_action("first_column", "Move to the first column", stepper(0, -utils.EDGE))
utils.register_action("last_column", "Move to the last column", stepper(0, utils.EDGE))
utils.register_action(
  "first_row",
  "Move to the top of the page, or to row N",
  row_jump_action("first_line")
)
utils.register_action(
  "last_row",
  "Move to the bottom of the page, or to row N",
  row_jump_action("last_line")
)
