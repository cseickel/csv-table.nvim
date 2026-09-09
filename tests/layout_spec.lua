local fixture = require("support.fixture")
local parse = require("csv-table.reader.parse")
local text = require("csv-table.utils.text")

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

--- The parsed page for `drawn`, numbered from `first_row_number`.
---@param first_row_number integer
---@return csv.Page
---@return csv.Column[] source_columns
local function parsed(first_row_number)
  local _, source = fixture.duplicated_headers()
  local result, err = parse.page(drawn(), {
    columns = { source[1] },
    first_row_number = first_row_number,
    file_version = "1:2:3",
  })
  truthy(result or err)
  return result, source
end

describe("parse.page", function()
  it("refuses text that is missing its borders", function()
    local result, err = parse.page({ "just", "some", "text", "here" }, {
      columns = {},
      first_row_number = 1,
      file_version = "",
    })
    equals(result, nil)
    equals(err, "xan view did not produce a table")
  end)

  it("finds the header and the data lines", function()
    local result = parsed(1)
    equals(result.header_line, 2)
    equals(result.first_line, 4)
    equals(result.last_line, 5)
    equals(result:row_count(), 2)
  end)

  it("reads the row ids out of the first cell", function()
    local result = parsed(1)
    equals(result:row_at_line(4).row_id, 7)
    equals(result:row_at_line(5).row_id, 9)
  end)

  it("numbers the rows from the number the page starts at", function()
    local result = parsed(1001)
    equals(result:row_at_line(4).row_number, 1001)
    equals(result:row_by_number(1002).row_id, 9)
  end)

  it("files each row under all three of its numbers", function()
    local result = parsed(1)
    local row = result:row_by_id(9)
    equals(row.row_number, 2)
    equals(row.buffer_line, 5)
    equals(result:row_by_number(2), row)
    equals(result:row_at_line(5), row)
  end)

  it("cuts the row id cell out of every line", function()
    local result = parsed(1)
    equals(result:column_count(), 1)
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
    equals(result:column_at(1), source[1])
    equals(result:column_number(source[1]), 1)
  end)

  it("answers nothing for a column that is off display", function()
    local result, source = parsed(1)
    equals(result:column_number(source[2]), nil)
  end)

  it("records the file version it was read at", function()
    local result = parsed(1)
    equals(result.file_version, "1:2:3")
  end)
end)

describe("page:column_number_at", function()
  it("names the column a byte falls in", function()
    local result = parsed(1)
    local range = result:cell_ranges(4)[1]
    equals(result:column_number_at(4, range.from), 1)
  end)

  it("answers with the last column for a byte past the table", function()
    local result = parsed(1)
    equals(result:column_number_at(4, 500), 1)
  end)
end)

describe("page:step_cell", function()
  it("walks to another row", function()
    local result, source = parsed(1)
    local cell = { row = result:row_at_line(4), column = source[1] }
    equals(result:step_cell(cell, { rows = 1, columns = 0 }).row.row_id, 9)
  end)

  it("stops at the last row on the page", function()
    local result, source = parsed(1)
    local cell = { row = result:row_at_line(4), column = source[1] }
    equals(result:step_cell(cell, { rows = 50, columns = 0 }).row.row_id, 9)
  end)

  it("stops at the first column", function()
    local result, source = parsed(1)
    local cell = { row = result:row_at_line(4), column = source[1] }
    equals(result:step_cell(cell, { rows = 0, columns = -50 }).column.column_id, 0)
  end)

  it("answers nothing when the column has left the display", function()
    local result, source = parsed(1)
    local cell = { row = result:row_at_line(4), column = source[2] }
    equals(result:step_cell(cell, { rows = 0, columns = 0 }), nil)
  end)
end)

describe("page:cell_width", function()
  it("measures a column without the padding view puts around it", function()
    local result = parsed(1)
    -- The header cell is drawn as `│ a   │`, so five characters hold `a` plus one
    -- space either side.
    equals(result:cell_width(1), 3)
  end)
end)

describe("page.empty", function()
  local page = require("csv-table.page")

  it("holds no rows and no columns", function()
    local empty = page.empty()
    equals(empty:row_count(), 0)
    equals(empty:column_count(), 0)
  end)

  it("answers every lookup with nothing", function()
    local empty = page.empty()
    equals(empty:row_at_line(1), nil)
    equals(empty:row_by_id(7), nil)
    equals(empty:column_at(1), nil)
    equals(empty:cell_at(1, 0), nil)
    equals(empty:cell_width(1), nil)
    equals(#empty:cell_ranges(1), 0)
  end)
end)

describe("text.truncate", function()
  it("leaves a value that fits", function()
    equals(text.truncate("abc", 5), "abc")
  end)

  it("ends a cut value in an ellipsis", function()
    equals(text.truncate("abcdef", 4), "abc…")
  end)

  it("counts characters rather than bytes", function()
    equals(text.length("a ▲"), 3)
  end)
end)
