--[[
The `csv.Query` methods for the cells picked out: an anchor cell, a head cell,
and a kind naming which of the two axes those cells bound.
]]

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

--- Pick out the block `kind` makes of two cells. One cell is picked by naming it
--- twice.
---@param anchor csv.Cell
---@param head csv.Cell
---@param kind csv.SelectionKind
function M.select_cells(self, anchor, head, kind)
  self.selection = { anchor = anchor, head = head, kind = kind }
end

--- Take the block out to `head`, leaving the anchor and the kind as they are.
--- Extending without a selection picks out the one cell.
---@param head csv.Cell
function M.extend_selection(self, head)
  if self.selection then
    self.selection.head = head
  else
    M.select_cells(self, head, head, "cell")
  end
end

--- Change which axes the block bounds, keeping both ends.
---@param kind csv.SelectionKind
function M.set_selection_kind(self, kind)
  if self.selection then
    self.selection.kind = kind
  end
end

function M.clear_selection(self)
  self.selection = nil
end

---@return boolean
function M.has_selection(self)
  return self.selection ~= nil
end

--- The lines and the columns the selection covers, present while both ends are
--- on the page. Rows are bounded by the lines they are drawn on, since a sort
--- puts row ids on the page in any order.
---@param page csv.Page
---@return csv.Bounds|nil
function M.selection_bounds(self, page)
  local selection = self.selection
  if not selection then
    return nil
  end

  local bounds = {
    top = page.first_line,
    bottom = page.last_line,
    left = 1,
    right = page:column_count(),
  }

  if selection.kind == "cell" or selection.kind == "row" then
    local anchor_line = selection.anchor.row.buffer_line
    local head_line = selection.head.row.buffer_line
    bounds.top = math.min(anchor_line, head_line)
    bounds.bottom = math.max(anchor_line, head_line)
  end

  if selection.kind == "cell" or selection.kind == "column" then
    local anchor_column = page:column_number(selection.anchor.column)
    local head_column = page:column_number(selection.head.column)
    if not anchor_column or not head_column then
      return nil
    end
    bounds.left = math.min(anchor_column, head_column)
    bounds.right = math.max(anchor_column, head_column)
  end

  return bounds
end

return M
