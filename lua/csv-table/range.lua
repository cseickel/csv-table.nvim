--[[
The block of cells the user has picked out.

A range is an anchor cell, a cursor cell, and everything between them. Both are
held as a source row id and a position among the columns on display, so a
render that moves a row up or down the page keeps the same cells selected.

Row ids do not order the range, because a sort puts them on the page in any
order, so the lines they are drawn on say which rows lie between the two ends.
A range with an end that is no longer on the page has nothing to draw and
nothing to copy, which is what `bounds` returning nothing means.

`csv-table.selection` says which columns the table shows, and this says which of
those cells the user has picked. `csv-table.state.marked` is a third thing
again: marks are scattered, they last, and they filter.

It is pure Lua and can be exercised without nvim.
]]

local M = {}

---@class csv.Row
---@field id integer
---@field index integer
---@field buffer csv.Buffer

---@class csv.Column
---@class label string
---@field index integer
---@field buffer csv.Buffer

---@class csv.CellRef
---@field row integer    Source row id.
---@field column integer Position among the columns on display, counting from one.

---@class csv.Range
---@field anchor csv.CellRef Where the selection started.
---@field cursor csv.CellRef Where it has been taken since.

---@class csv.Bounds
---@field top integer    Line the range starts on.
---@field bottom integer Line it ends on.
---@field left integer   Leftmost column position.
---@field right integer  Rightmost column position.

---@param buffer csv.Buffer
---@param index integer
---@return csv.Row|nil
function M.get_row_by_index(buffer, index)
  local layout = buffer.layout
  if not layout then
    return nil
  end
  local id = layout.row_id_by_index[index]
  if not id then
    return nil
  end
  return { id = id, index = index, buffer = buffer }
end

---@param buffer csv.Buffer
---@param id integer
---@return csv.Row|nil
function M.get_row_by_id(buffer, id)
  local layout = buffer.layout
  if not layout then
    return nil
  end
  local index = layout.row_index_by_id[id]
  if not index then
    return nil
  end
  return { id = id, index = index, buffer = buffer }
end

function M.get_column_by_index(buffer, index)
  local layout = buffer.layout
  if not layout then
    return nil
  end
  return layout.columns[index]
end

--- Select the rectangle between two cells. One cell is selected by naming it
--- twice.
---@param state csv.State
---@param anchor csv.CellRef
---@param cursor csv.CellRef
function M.set(state, anchor, cursor)
  state.range = { anchor = anchor, cursor = cursor }
end

--- Take the running selection out to `cell`, leaving the anchor where it is.
---@param state csv.State
---@param cell csv.CellRef
function M.extend(state, cell)
  if not state.range then
    return M.set(state, cell, cell)
  end
  state.range = { anchor = state.range.anchor, cursor = cell }
end

---@param state csv.State
function M.clear(state)
  state.range = nil
end

---@param state csv.State
---@return boolean
function M.active(state)
  return state.range ~= nil
end

--- The lines and the columns the range covers, or nothing when either end has
--- left the page.
---@param state csv.State
---@param layout csv.Layout
---@return csv.Bounds|nil
function M.bounds(state, layout)
  local range = state.range
  if not range then
    return nil
  end

  local anchor_line = layout.row_index_by_id[range.anchor.row]
  local cursor_line = layout.row_index_by_id[range.cursor.row]
  if not anchor_line or not cursor_line then
    return nil
  end

  return {
    top = math.min(anchor_line, cursor_line),
    bottom = math.max(anchor_line, cursor_line),
    left = math.min(range.anchor.column, range.cursor.column),
    right = math.max(range.anchor.column, range.cursor.column),
  }
end

--- Where a cell reference lands when it is taken `rows` down and `columns`
--- across, kept on the page and among the columns on display. The end of a
--- selection walks with this rather than with the cursor, so a selection can
--- reach past the cell the user is looking at.
---@param cell csv.CellRef
---@param layout csv.Layout
---@param delta { rows: integer, columns: integer, column_count: integer } `column_count` is how many columns are on display.
---@return csv.CellRef|nil
function M.step(cell, layout, delta)
  local line = layout.row_index_by_id[cell.row]
  if not line then
    return nil
  end

  local target_line = math.min(math.max(line + delta.rows, layout.first_row), layout.last_row)
  local row = layout.row_id_by_index[target_line]
  if not row then
    return nil
  end

  return {
    row = row,
    column = math.min(math.max(cell.column + delta.columns, 1), delta.column_count),
  }
end

--- How many rows and columns the range covers.
---@param bounds csv.Bounds
---@return integer rows
---@return integer columns
function M.size(bounds)
  return bounds.bottom - bounds.top + 1, bounds.right - bounds.left + 1
end

return M
