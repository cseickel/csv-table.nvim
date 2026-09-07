local fixture = require("support.fixture")
local layout = require("csv-table.layout")
local selection = require("csv-table.selection")

--- A three row, two column layout to pick cells out of.
---@return csv.Layout
---@return csv.State
---@return csv.Column[]
local function drawn()
  local view, source = fixture.duplicated_headers()
  local lines = {
    "",
    "┌────┬─────┬─────┐",
    "│ id │ a   │ b   │",
    "├────┼─────┼─────┤",
    "│ 7  │ x   │ p   │",
    "│ 9  │ y   │ q   │",
    "│ 4  │ z   │ r   │",
    "└────┴─────┴─────┘",
    "",
  }
  local result = layout.parse(lines, { source[1], source[2] }, 1)
  return result, view, source
end

---@param result csv.Layout
---@param buffer_line integer
---@param column_number integer
---@return csv.Cell
local function cell_at(result, buffer_line, column_number)
  return {
    row = layout.row_at_line(result, buffer_line),
    column = layout.column_at(result, column_number),
  }
end

describe("selection.set", function()
  it("covers the rectangle between the two cells", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 6, 2), "cell")

    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("covers one cell when the same cell is named twice", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    selection.set(view, cell, cell, "cell")

    local rows, cols = selection.size(selection.bounds(view, result))
    equals(rows, 1)
    equals(cols, 1)
  end)

  it("orders the bounds however the two ends were given", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 6, 2), cell_at(result, 4, 1), "cell")

    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.left, 1)
  end)
end)

describe("selection.bounds by kind", function()
  it("takes every column for a row selection", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 5, 1), "row")

    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("takes every row for a column selection", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    selection.set(view, cell, cell, "column")

    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 2)
    equals(bounds.right, 2)
  end)

  it("takes the whole page", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    selection.set(view, cell, cell, "page")

    local rows, cols = selection.size(selection.bounds(view, result))
    equals(rows, 3)
    equals(cols, 2)
  end)

  it("answers for a row selection whose column has gone", function()
    local result, view, source = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 5, 1), "row")
    view.selection.head = { row = view.selection.head.row, column = source[3] }

    equals(selection.bounds(view, result).bottom, 5)
  end)
end)

describe("selection.extend", function()
  it("moves the head and leaves the anchor and the kind", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 4, 1), "row")
    selection.extend(view, cell_at(result, 6, 2))

    equals(view.selection.kind, "row")
    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
  end)

  it("picks out the one cell when nothing is selected yet", function()
    local result, view = drawn()
    selection.extend(view, cell_at(result, 5, 1))

    equals(view.selection.kind, "cell")
    local rows, cols = selection.size(selection.bounds(view, result))
    equals(rows, 1)
    equals(cols, 1)
  end)
end)

describe("selection.set_kind", function()
  it("keeps both ends", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 5, 1), "cell")
    selection.set_kind(view, "row")

    local bounds = selection.bounds(view, result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.right, 2)
  end)
end)

describe("selection.clear", function()
  it("leaves nothing to draw", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    selection.clear(view)

    equals(selection.is_set(view), false)
    equals(selection.bounds(view, result), nil)
  end)
end)

describe("selection.bounds", function()
  it("answers nothing once an end has left the display", function()
    local result, view, source = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    view.selection.head = { row = view.selection.head.row, column = source[3] }

    equals(selection.bounds(view, result), nil)
  end)
end)

describe("selection.size", function()
  it("counts the rows and the columns it covers", function()
    local result, view = drawn()
    selection.set(view, cell_at(result, 4, 1), cell_at(result, 6, 2), "cell")

    local rows, cols = selection.size(selection.bounds(view, result))
    equals(rows, 3)
    equals(cols, 2)
  end)
end)
