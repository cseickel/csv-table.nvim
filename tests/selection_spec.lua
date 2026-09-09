local fixture = require("support.fixture")
local parse = require("csv-table.reader.parse")

--- A three row, two column page to pick cells out of.
---@return csv.Page
---@return csv.Query
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
  local result = parse.page(lines, {
    columns = { source[1], source[2] },
    first_row_number = 1,
    file_version = "",
  })
  return result, view, source
end

---@param result csv.Page
---@param buffer_line integer
---@param column_number integer
---@return csv.Cell
local function cell_at(result, buffer_line, column_number)
  return { row = result:row_at_line(buffer_line), column = result:column_at(column_number) }
end

---@param bounds csv.Bounds
---@return integer rows
---@return integer columns
local function size(bounds)
  return bounds.bottom - bounds.top + 1, bounds.right - bounds.left + 1
end

describe("query:select_cells", function()
  it("covers the rectangle between the two cells", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 6, 2), "cell")

    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("covers one cell when the same cell is named twice", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    view:select_cells(cell, cell, "cell")

    local rows, cols = size(view:selection_bounds(result))
    equals(rows, 1)
    equals(cols, 1)
  end)

  it("orders the bounds however the two ends were given", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 6, 2), cell_at(result, 4, 1), "cell")

    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.left, 1)
  end)
end)

describe("query:selection_bounds by kind", function()
  it("takes every column for a row selection", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "row")

    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("takes every row for a column selection", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    view:select_cells(cell, cell, "column")

    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 2)
    equals(bounds.right, 2)
  end)

  it("takes the whole page", function()
    local result, view = drawn()
    local cell = cell_at(result, 5, 2)
    view:select_cells(cell, cell, "page")

    local rows, cols = size(view:selection_bounds(result))
    equals(rows, 3)
    equals(cols, 2)
  end)

  it("answers for a row selection whose column has gone", function()
    local result, view, source = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "row")
    view.selection.head = { row = view.selection.head.row, column = source[3] }

    equals(view:selection_bounds(result).bottom, 5)
  end)
end)

describe("query:extend_selection", function()
  it("moves the head and leaves the anchor and the kind", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "row")
    view:extend_selection(cell_at(result, 6, 2))

    equals(view.selection.kind, "row")
    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
  end)

  it("picks out the one cell when nothing is selected yet", function()
    local result, view = drawn()
    view:extend_selection(cell_at(result, 5, 1))

    equals(view.selection.kind, "cell")
    local rows, cols = size(view:selection_bounds(result))
    equals(rows, 1)
    equals(cols, 1)
  end)
end)

describe("query:set_selection_kind", function()
  it("keeps both ends", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "cell")
    view:set_selection_kind("row")

    local bounds = view:selection_bounds(result)
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.right, 2)
  end)
end)

describe("query:clear_selection", function()
  it("leaves nothing to draw", function()
    local result, view = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    view:clear_selection()

    equals(view:has_selection(), false)
    equals(view:selection_bounds(result), nil)
  end)
end)

describe("query:selection_bounds", function()
  it("answers nothing once an end has left the display", function()
    local result, view, source = drawn()
    view:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    view.selection.head = { row = view.selection.head.row, column = source[3] }

    equals(view:selection_bounds(result), nil)
  end)
end)
