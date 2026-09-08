--[[
Draws extmarks over the rendered table for:
- marked rows
- marked columns
- the selection

`redraw` clears the namespace and draws all three again.
]]

local layout_module = require("csv-table.layout")
local selection = require("csv-table.selection")

local M = {}

local namespace = vim.api.nvim_create_namespace("csv-marks")

-- Above the 4096 an extmark takes by default, so a selected cell draws over the
-- row highlight it may be sitting on.
M.SELECTION_PRIORITY = 4200

--- Draw the marked rows and the marked columns.
---@param buffer csv.Buffer
local function draw_marks(buffer)
  local layout = buffer.layout
  for buffer_line = layout.first_line, layout.last_line do
    local row = layout_module.row_at_line(layout, buffer_line)
    if row and buffer.state.marked[row.row_id] then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, buffer_line - 1, 0, {
        line_hl_group = "CsvMarkedRow",
      })
    end
  end

  for column_number, column in ipairs(layout.columns) do
    if buffer.state.marked_columns[column.column_id] then
      local from, to = layout_module.cell_bounds(layout, layout.header_line, column_number)
      if from then
        vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, layout.header_line - 1, from, {
          end_col = to,
          hl_group = "CsvMarkedColumn",
        })
      end
    end
  end
end

--- Draw the selected cells. The selected columns are next to each other, so one
--- extmark per line spans the first column's left edge to the last one's right.
---@param buffer csv.Buffer
local function draw_selection(buffer)
  local bounds = selection.bounds(buffer.state, buffer.layout)
  if not bounds then
    return
  end

  for line = bounds.top, bounds.bottom do
    local cells = layout_module.cell_ranges(buffer.layout, line)
    local first, last = cells[bounds.left], cells[bounds.right]
    if first and last then
      vim.api.nvim_buf_set_extmark(buffer.bufnr, namespace, line - 1, first.from, {
        end_col = last.to,
        hl_group = "CsvSelection",
        priority = M.SELECTION_PRIORITY,
      })
    end
  end
end

---@param buffer csv.Buffer
function M.redraw(buffer)
  if not buffer.layout then
    return
  end
  vim.api.nvim_buf_clear_namespace(buffer.bufnr, namespace, 0, -1)
  draw_marks(buffer)
  draw_selection(buffer)
end

return M
