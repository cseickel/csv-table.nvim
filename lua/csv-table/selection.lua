--[[
The block of cells the user has picked out.

A selection is an anchor cell, a head cell, and a kind saying which of the two
axes those cells bound. The head is where the active cell was at the last
extend, so a plain move leaves the block where the user put it and the next
extend takes the block to wherever they have since walked.

Both cells name a row and a column of the layout on screen, and
`csv-table.buffer.render` clears the selection before it replaces that layout,
so both ends belong to the text the user picked them from.

The lines the rows are drawn on say which rows lie between the two ends, because
a sort puts row ids on the page in any order.

`csv-table.state.marked` is the other way to pick rows out: marks are scattered,
they last across renders, and they filter.
]]

local layout_module = require("csv-table.layout")

local M = {}

--- Which axis the two cells bound, and which one covers the page.
---
--- `cell` bounds both, `row` bounds the rows and takes every column, `column`
--- bounds the columns and takes every row, and `page` takes everything.
---@alias csv.SelectionKind "cell"|"row"|"column"|"page"

---@class csv.Selection
---@field anchor csv.Cell Where selecting started.
---@field head csv.Cell   Where the active cell was at the last extend.
---@field kind csv.SelectionKind

---@class csv.Bounds
---@field top integer    Line the selection starts on.
---@field bottom integer Line it ends on.
---@field left integer   Leftmost column number.
---@field right integer  Rightmost column number.

--- Pick out the block `kind` makes of two cells. One cell is picked by naming
--- it twice.
---@param state csv.State
---@param anchor csv.Cell
---@param head csv.Cell
---@param kind csv.SelectionKind
function M.set(state, anchor, head, kind)
  state.selection = { anchor = anchor, head = head, kind = kind }
end

--- Take the block out to `head`, leaving the anchor and the kind as they are.
--- Extending without a selection picks out the one cell.
---@param state csv.State
---@param head csv.Cell
function M.extend(state, head)
  local selection = state.selection
  if selection then
    selection.head = head
  else
    M.set(state, head, head, "cell")
  end
end

--- Change which axes the block bounds, keeping both ends.
---@param state csv.State
---@param kind csv.SelectionKind
function M.set_kind(state, kind)
  if state.selection then
    state.selection.kind = kind
  end
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

  local bounds = {
    top = layout.first_line,
    bottom = layout.last_line,
    left = 1,
    right = layout_module.column_count(layout),
  }

  if selection.kind == "cell" or selection.kind == "row" then
    local anchor_line = selection.anchor.row.buffer_line
    local head_line = selection.head.row.buffer_line
    bounds.top = math.min(anchor_line, head_line)
    bounds.bottom = math.max(anchor_line, head_line)
  end

  if selection.kind == "cell" or selection.kind == "column" then
    local anchor_column = layout_module.column_number(layout, selection.anchor.column)
    local head_column = layout_module.column_number(layout, selection.head.column)
    if not anchor_column or not head_column then
      return nil
    end
    bounds.left = math.min(anchor_column, head_column)
    bounds.right = math.max(anchor_column, head_column)
  end

  return bounds
end

--- How many rows and columns the selection covers.
---@param bounds csv.Bounds
---@return integer rows
---@return integer columns
function M.size(bounds)
  return bounds.bottom - bounds.top + 1, bounds.right - bounds.left + 1
end

return M
