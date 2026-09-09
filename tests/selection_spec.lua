local fixture = require("support.fixture")
local parse = require("csv-table.reader.parse")
local view = require("csv-table.view")

--- A three row, two column page, and a view of it to pick cells out of.
---@return csv.Page
---@return csv.View
---@return csv.Column[]
local function drawn()
  local query, source = fixture.duplicated_headers()
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
  return result, view.new({ bufnr = 1, page = result, query = query }, 1000), source
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

describe("view:select_cells", function()
  it("covers the rectangle between the two cells", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 6, 2), "cell")

    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("covers one cell when the same cell is named twice", function()
    local result, picked = drawn()
    local cell = cell_at(result, 5, 2)
    picked:select_cells(cell, cell, "cell")

    local rows, cols = size(picked:bounds())
    equals(rows, 1)
    equals(cols, 1)
  end)

  it("orders the bounds however the two ends were given", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 6, 2), cell_at(result, 4, 1), "cell")

    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.left, 1)
  end)
end)

describe("view:bounds by kind", function()
  it("takes every column for a row selection", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "row")

    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.left, 1)
    equals(bounds.right, 2)
  end)

  it("takes every row for a column selection", function()
    local result, picked = drawn()
    local cell = cell_at(result, 5, 2)
    picked:select_cells(cell, cell, "column")

    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
    equals(bounds.left, 2)
    equals(bounds.right, 2)
  end)

  it("takes the whole page", function()
    local result, picked = drawn()
    local cell = cell_at(result, 5, 2)
    picked:select_cells(cell, cell, "page")

    local rows, cols = size(picked:bounds())
    equals(rows, 3)
    equals(cols, 2)
  end)

  it("answers for a row selection whose column has gone", function()
    local result, picked, source = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "row")
    picked.head = { row_id = picked.head.row_id, column_id = source[3].column_id }

    equals(picked:bounds().bottom, 5)
  end)
end)

describe("view:extend_selection", function()
  it("moves the head and leaves the anchor and the kind", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "row")
    picked:extend_selection(cell_at(result, 6, 2))

    equals(picked.kind, "row")
    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.bottom, 6)
  end)

  it("picks out the one cell when nothing is selected yet", function()
    local result, picked = drawn()
    picked:extend_selection(cell_at(result, 5, 1))

    equals(picked.kind, "cell")
    local rows, cols = size(picked:bounds())
    equals(rows, 1)
    equals(cols, 1)
  end)
end)

describe("view:set_kind", function()
  it("keeps both ends", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 5, 1), "cell")
    picked:set_kind("row")

    local bounds = picked:bounds()
    equals(bounds.top, 4)
    equals(bounds.bottom, 5)
    equals(bounds.right, 2)
  end)
end)

describe("view:clear_selection", function()
  it("leaves nothing to draw", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    picked:clear_selection()

    equals(picked:has_selection(), false)
    equals(picked:bounds(), nil)
  end)
end)

describe("view:bounds", function()
  it("answers nothing once an end has left the display", function()
    local result, picked, source = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 4, 1), "cell")
    picked.head = { row_id = picked.head.row_id, column_id = source[3].column_id }

    equals(picked:bounds(), nil)
  end)

  it("answers nothing once an end has left the page", function()
    local result, picked = drawn()
    picked:select_cells(cell_at(result, 4, 1), cell_at(result, 6, 2), "cell")
    picked.head = { row_id = 99, column_id = picked.head.column_id }

    equals(picked:bounds(), nil)
  end)
end)

describe("view:active_bounds", function()
  it("is the one cell the user is on", function()
    local result, picked = drawn()
    picked.active = { row_id = 9, column_id = result:column_at(2).column_id }

    local bounds = picked:active_bounds()
    equals(bounds.top, 5)
    equals(bounds.bottom, 5)
    equals(bounds.left, 2)
    equals(bounds.right, 2)
  end)

  it("is absent before the first render", function()
    local _, picked = drawn()
    equals(picked:active_bounds(), nil)
  end)
end)
