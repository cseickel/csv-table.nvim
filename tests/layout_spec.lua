local columns = require("csv-table.columns")
local fixture = require("support.fixture")
local layout = require("csv-table.layout")
local parse = require("csv-table.reader.parse")

--- What `xan view -t table` draws for two rows of one column, blank padding and
--- all.
---@return string[]
local function drawn()
  return {
    "",
    "┌────┬─────┐",
    "│ id │ a   │",
    "├────┼─────┤",
    "│ 7  │ x   │",
    "│ 9  │ y   │",
    "└────┴─────┘",
    "",
  }
end

--- The parsed layout for `drawn`, numbered from `first_row_number`.
---@param first_row_number integer
---@return csv.Layout
---@return csv.Column[] source_columns
local function parsed(first_row_number)
  local _, source = fixture.duplicated_headers()
  local result, err = parse.page(drawn(), { source[1] }, first_row_number)
  truthy(result or err)
  return result, source
end

describe("parse.page", function()
  it("refuses text that is missing its borders", function()
    local result, err = parse.page({ "just", "some", "text", "here" }, {}, 1)
    equals(result, nil)
    equals(err, "xan view did not produce a table")
  end)

  it("finds the header and the data lines", function()
    local result = parsed(1)
    equals(result.header_line, 2)
    equals(result.first_line, 4)
    equals(result.last_line, 5)
    equals(layout.row_count(result), 2)
  end)

  it("reads the row ids out of the first cell", function()
    local result = parsed(1)
    equals(layout.row_at_line(result, 4).row_id, 7)
    equals(layout.row_at_line(result, 5).row_id, 9)
  end)

  it("numbers the rows from the number the page starts at", function()
    local result = parsed(1001)
    equals(layout.row_at_line(result, 4).row_number, 1001)
    equals(layout.row_by_number(result, 1002).row_id, 9)
  end)

  it("files each row under all three of its numbers", function()
    local result = parsed(1)
    local row = layout.row_by_id(result, 9)
    equals(row.row_number, 2)
    equals(row.buffer_line, 5)
    equals(layout.row_by_number(result, 2), row)
    equals(layout.row_at_line(result, 5), row)
  end)

  it("cuts the row id cell out of every line", function()
    local result = parsed(1)
    equals(layout.column_count(result), 1)
    lacks(result.lines[result.header_line], "id")
  end)

  it("keeps the table's own border lines", function()
    local result = parsed(1)
    matches(result.lines[1], "┌")
    matches(result.lines[3], "├")
    matches(result.lines[#result.lines], "└")
  end)

  it("places the columns it was handed", function()
    local result, source = parsed(1)
    equals(layout.column_at(result, 1), source[1])
    equals(layout.column_number(result, source[1]), 1)
  end)

  it("answers nothing for a column that is off display", function()
    local result, source = parsed(1)
    equals(layout.column_number(result, source[2]), nil)
  end)
end)

describe("layout.column_number_at", function()
  it("names the column a byte falls in", function()
    local result = parsed(1)
    local range = layout.cell_ranges(result, 4)[1]
    equals(layout.column_number_at(result, 4, range.from), 1)
  end)

  it("answers with the last column for a byte past the table", function()
    local result = parsed(1)
    equals(layout.column_number_at(result, 4, 500), 1)
  end)
end)

describe("layout.step_cell", function()
  it("walks to another row", function()
    local result, source = parsed(1)
    local cell = { row = layout.row_at_line(result, 4), column = source[1] }
    local stepped = layout.step_cell(result, cell, { rows = 1, columns = 0 })
    equals(stepped.row.row_id, 9)
  end)

  it("stops at the last row on the page", function()
    local result, source = parsed(1)
    local cell = { row = layout.row_at_line(result, 4), column = source[1] }
    local stepped = layout.step_cell(result, cell, { rows = 50, columns = 0 })
    equals(stepped.row.row_id, 9)
  end)

  it("stops at the first column", function()
    local result, source = parsed(1)
    local cell = { row = layout.row_at_line(result, 4), column = source[1] }
    local stepped = layout.step_cell(result, cell, { rows = 0, columns = -50 })
    equals(stepped.column.column_id, 0)
  end)

  it("answers nothing when the column has left the display", function()
    local result, source = parsed(1)
    local cell = { row = layout.row_at_line(result, 4), column = source[2] }
    equals(layout.step_cell(result, cell, { rows = 0, columns = 0 }), nil)
  end)
end)

describe("layout.cell_width", function()
  it("measures a column without the padding view puts around it", function()
    local result = parsed(1)
    -- The header cell is drawn as `│ a   │`, so five characters hold `a` plus
    -- one space either side.
    equals(layout.cell_width(result, 1), 3)
  end)
end)

describe("columns.truncate", function()
  it("leaves a value that fits", function()
    equals(columns.truncate("abc", 5), "abc")
  end)

  it("ends a cut value in an ellipsis", function()
    equals(columns.truncate("abcdef", 4), "abc…")
  end)

  it("counts characters rather than bytes", function()
    equals(columns.text_length("a ▲"), 3)
  end)
end)
