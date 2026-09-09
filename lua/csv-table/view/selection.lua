--[[
The `csv.View` methods for the cells picked out: an anchor cell, a head cell, and
a kind naming which of the two axes those cells bound.

Both ends are `csv.CellRef`, so nothing here holds a row of a page that is no
longer drawn. `csv-table.buffer` drops them when a render moves the rows.
]]

local page = require("csv-table.page")

local M = {}

--- Which axis the two cells bound, and which one covers the page.
---
--- `cell` bounds both, `row` bounds the rows and takes every column, `column`
--- bounds the columns and takes every row, and `page` takes everything.
---@alias csv.SelectionKind "cell"|"row"|"column"|"page"

---@class csv.Bounds
---@field top integer    Line the selection starts on.
---@field bottom integer Line it ends on.
---@field left integer   Leftmost column number.
---@field right integer  Rightmost column number.

---@param drawn csv.Page
---@param ref csv.CellRef
---@return integer|nil
local function column_number_of(drawn, ref)
  local column = drawn:column_by_id(ref.column_id)
  return column and drawn:column_number(column) or nil
end

--- Pick out the block `kind` makes of two cells. One cell is picked by naming it
--- twice.
---@param anchor csv.Cell
---@param head csv.Cell
---@param kind csv.SelectionKind
function M.select_cells(self, anchor, head, kind)
  self.anchor = page.ref_of(anchor)
  self.head = page.ref_of(head)
  self.kind = kind
end

--- Take the block out to `head`, leaving the anchor and the kind as they are.
--- Extending without a selection picks out the one cell.
---@param head csv.Cell
function M.extend_selection(self, head)
  if self.anchor then
    self.head = page.ref_of(head)
  else
    self:select_cells(head, head, "cell")
  end
end

--- Change which axes the block bounds, keeping both ends.
---@param kind csv.SelectionKind
function M.set_kind(self, kind)
  if self.anchor then
    self.kind = kind
  end
end

function M.clear_selection(self)
  self.anchor = nil
  self.head = nil
end

---@return boolean
function M.has_selection(self)
  return self.anchor ~= nil
end

--- The lines and the columns the selection covers, present while the ends the kind
--- bounds are on the page. Rows are bounded by the lines they are drawn on, since
--- a sort puts row ids on the page in any order.
---
--- Each axis is looked up only where the kind bounds it, so hiding a column leaves
--- a selection of whole rows alone.
---@return csv.Bounds|nil
function M.bounds(self)
  if not self.anchor or not self.head then
    return nil
  end

  local drawn = self.buffer.page
  local bounds = {
    top = drawn.first_line,
    bottom = drawn.last_line,
    left = 1,
    right = drawn:column_count(),
  }

  if self.kind == "cell" or self.kind == "row" then
    local anchor = drawn:row_by_id(self.anchor.row_id)
    local head = drawn:row_by_id(self.head.row_id)
    if not anchor or not head then
      return nil
    end
    bounds.top = math.min(anchor.buffer_line, head.buffer_line)
    bounds.bottom = math.max(anchor.buffer_line, head.buffer_line)
  end

  if self.kind == "cell" or self.kind == "column" then
    local left = column_number_of(drawn, self.anchor)
    local right = column_number_of(drawn, self.head)
    if not left or not right then
      return nil
    end
    bounds.left = math.min(left, right)
    bounds.right = math.max(left, right)
  end

  return bounds
end

--- The active cell on its own, as the bounds of a block of one, which is what an
--- export with nothing selected takes.
---@return csv.Bounds|nil
function M.active_bounds(self)
  local cell = self:active_cell()
  if not cell then
    return nil
  end
  local column_number = self.buffer.page:column_number(cell.column)
  if not column_number then
    return nil
  end
  return {
    top = cell.row.buffer_line,
    bottom = cell.row.buffer_line,
    left = column_number,
    right = column_number,
  }
end

--- Leave the selected block in `'<` and `'>`, so nvim's own `gv` reselects those
--- cells rather than the two ends nvim was holding.
---
--- Nvim writes both marks itself when a visual mode ends, so `csv-table.buffer`
--- runs this again on the way out and lands last.
---
--- The marks outlive a render, the same way they do in a buffer of text that was
--- replaced: they name a line and a byte, and after a sort those name different
--- rows.
---
--- `nvim_buf_set_mark` refuses `<` and `>`, so `setpos` does the writing, and it
--- writes nothing unless the buffer is the one the user is in.
function M.mark_selection(self)
  local bounds = self:bounds()
  if not bounds then
    return
  end

  local drawn = self.buffer.page
  local first = drawn:cell_ranges(bounds.top)[bounds.left]
  local last = drawn:cell_ranges(bounds.bottom)[bounds.right]
  if first and last then
    vim.fn.setpos("'<", { self.buffer.bufnr, bounds.top, first.from + 1, 0 })
    vim.fn.setpos("'>", { self.buffer.bufnr, bounds.bottom, last.to, 0 })
  end
end

return M
