--[[
The block of cells the user has picked out.

A selection is an anchor cell, a head cell, and everything between them. Both
name a row and a column of the layout on screen, and `csv-table.buffer.render`
clears the selection before it replaces that layout, so both ends belong to the
text the user picked them from.

The lines the rows are drawn on say which rows lie between the two ends, because
a sort puts row ids on the page in any order.

`csv-table.state.marked` is the other way to pick rows out: marks are scattered,
they last across renders, and they filter.
]]

local layout_module = require("csv-table.layout")

local M = {}

---@class csv.Selection
---@field anchor csv.Cell Where the selection started.
---@field head csv.Cell   Where it has been taken since.

---@class csv.Bounds
---@field top integer    Line the selection starts on.
---@field bottom integer Line it ends on.
---@field left integer   Leftmost column number.
---@field right integer  Rightmost column number.

--- Select the rectangle between two cells. One cell is selected by naming it
--- twice.
---@param state csv.State
---@param anchor csv.Cell
---@param head csv.Cell
function M.set(state, anchor, head)
  state.selection = { anchor = anchor, head = head }
end

--- Take the running selection out to `cell`, leaving the anchor where it is.
---@param state csv.State
---@param cell csv.Cell
function M.extend(state, cell)
  if not state.selection then
    return M.set(state, cell, cell)
  end
  state.selection = { anchor = state.selection.anchor, head = cell }
end

---@param state csv.State
function M.clear(state)
  state.selection = nil
end

---@param state csv.State
---@return boolean
function M.is_set(state)
  return state.selection ~= nil
end

--- The lines and the columns the selection covers, present while both ends are
--- on the page.
---@param state csv.State
---@param layout csv.Layout
---@return csv.Bounds|nil
function M.bounds(state, layout)
  local selection = state.selection
  if not selection then
    return nil
  end

  local anchor_column = layout_module.column_number(layout, selection.anchor.column)
  local head_column = layout_module.column_number(layout, selection.head.column)
  if not anchor_column or not head_column then
    return nil
  end

  local anchor_line = selection.anchor.row.buffer_line
  local head_line = selection.head.row.buffer_line
  return {
    top = math.min(anchor_line, head_line),
    bottom = math.max(anchor_line, head_line),
    left = math.min(anchor_column, head_column),
    right = math.max(anchor_column, head_column),
  }
end

--- How many rows and columns the selection covers.
---@param bounds csv.Bounds
---@return integer rows
---@return integer columns
function M.size(bounds)
  return bounds.bottom - bounds.top + 1, bounds.right - bounds.left + 1
end

return M
