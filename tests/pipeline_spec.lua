local columns = require("csv-table.columns")
local commands = require("csv-table.reader.commands")
local expression = require("csv-table.reader.expression")
local fixture = require("support.fixture")
local pipeline = require("csv-table.reader.pipeline")
local state = require("csv-table.state")

--- The pipeline string for the current state, with every column on display.
---@param view csv.State
---@return string
local function built(view)
  return pipeline.build(view, columns.display_columns(view))
end

--- The position lookup for the current state.
---@param view csv.State
---@return table<integer, integer>
local function positions_for(view)
  local _, positions = pipeline.carried_columns(view, columns.display_columns(view))
  return positions
end

describe("pipeline.carried_columns", function()
  it("lands the row id at zero and each column at its place in the list", function()
    local view, _ = fixture.duplicated_headers()
    local carried, positions = pipeline.carried_columns(view, columns.display_columns(view))

    equals(#carried, 3)
    equals(positions[0], 1)
    equals(positions[1], 2)
    equals(positions[2], 3)
  end)

  it("carries a hidden column that a sort key names", function()
    local view, source = fixture.duplicated_headers()
    columns.hide(source[3])
    state.sort_by(view, source[3], "desc")

    local carried = pipeline.carried_columns(view, columns.display_columns(view))
    equals(#carried, 3)
    equals(carried[3].column_id, 2)
  end)

  it("carries a hidden column that a filter names", function()
    local view, source = fixture.duplicated_headers()
    columns.hide(source[2])
    state.add_filter(view, {
      type = "string",
      column = source[2],
      operator = "contains",
      value = "x",
    })

    local carried = pipeline.carried_columns(view, columns.display_columns(view))
    equals(#carried, 3)
    equals(carried[3].column_id, 1)
  end)
end)

describe("pipeline.build", function()
  it("opens by selecting the carried columns and prepending the row id", function()
    local view, _ = fixture.duplicated_headers()
    matches(built(view), "^select '0,1,2' | enum %-c 'id'")
  end)

  it("sorts by the position the opening select fixed", function()
    local view, source = fixture.duplicated_headers()
    state.sort_by(view, source[3], "desc")
    matches(built(view), "sort %-s 3 %-R")
  end)

  it("sorts numerically when the column holds numbers", function()
    local view, source = fixture.duplicated_headers()
    view.formats[source[1].column_id] = { kind = "int", precision = 0 }
    state.sort_by(view, source[1], "asc")
    matches(built(view), "sort %-s 1 %-N")
  end)

  it("applies the sort keys least significant first", function()
    local view, source = fixture.duplicated_headers()
    state.sort_by(view, source[1], "asc")
    state.add_sort_key(view, source[3], "asc")

    local pipeline_string = built(view)
    local significant = pipeline_string:find("sort %-s 1")
    local minor = pipeline_string:find("sort %-s 3")
    truthy(minor < significant)
  end)

  it("slices the page the state asks for", function()
    local view, _ = fixture.duplicated_headers()
    view.page = 2
    view.limit = 100
    matches(built(view), "slice %-s 200 %-l 100")
  end)

  it("closes by naming the row id and each displayed column", function()
    local view, _ = fixture.duplicated_headers()
    matches(built(view), 'select %-e \'col%(0%) as "id"')
    matches(built(view), 'col%(1%) || " " as "a%[0%]"')
  end)

  it("leaves a hidden column out of the closing select", function()
    local view, source = fixture.duplicated_headers()
    columns.hide(source[3])
    state.sort_by(view, source[3], "desc")

    local pipeline_string = built(view)
    matches(pipeline_string, "sort %-s 3")
    lacks(pipeline_string, 'as "a%[1%]')
  end)

  it("marks a sorted column in its header", function()
    local view, source = fixture.duplicated_headers()
    state.sort_by(view, source[1], "asc")
    matches(built(view), 'as "a%[0%] ▲"')
  end)

  it("numbers the arrows when several keys are in play", function()
    local view, source = fixture.duplicated_headers()
    state.sort_by(view, source[1], "asc")
    state.add_sort_key(view, source[3], "desc")

    local pipeline_string = built(view)
    matches(pipeline_string, 'as "a%[0%] ▲1"')
    matches(pipeline_string, 'as "a%[1%] ▼2"')
  end)

  it("cuts a header down to the width the user pinned", function()
    local view, source = fixture.duplicated_headers()
    view.formats[source[1].column_id] = {
      kind = "text",
      precision = 0,
      width = 3,
      align = "left",
    }
    matches(built(view), 'as "a%[…"')
  end)

  it("right aligns the numeric columns by their drawn position", function()
    local view, source = fixture.duplicated_headers()
    view.formats[source[2].column_id] = { kind = "float", precision = 2 }
    matches(built(view), "%-r '2'")
  end)
end)

describe("expression.all_filters", function()
  it("addresses a column by the position the opening select fixed", function()
    local view, source = fixture.duplicated_headers()
    state.add_filter(view, {
      type = "string",
      column = source[3],
      operator = "contains",
      value = "x",
    })
    equals(expression.all_filters(view, positions_for(view)), 'contains(col(3), "x")')
  end)

  it("wraps a numeric comparison so a value that fails to cast drops out", function()
    local view, source = fixture.duplicated_headers()
    state.add_filter(view, {
      type = "numeric",
      column = source[1],
      operator = ">=",
      value = 10,
    })
    equals(expression.all_filters(view, positions_for(view)), "try(col(1) >= 10)")
  end)

  it("reads the marked rows off the row id at zero", function()
    local view, _ = fixture.duplicated_headers()
    state.toggle_mark(view, 7)
    state.toggle_mark(view, 3)
    state.add_filter(view, { type = "marked" })
    equals(expression.all_filters(view, positions_for(view)), '(col(0) in ["3", "7"])')
  end)

  it("ANDs several filters together", function()
    local view, source = fixture.duplicated_headers()
    state.add_filter(view, { type = "expr", expression = "true" })
    state.add_filter(view, {
      type = "in",
      column = source[1],
      values = { "x", "y" },
    })
    equals(
      expression.all_filters(view, positions_for(view)),
      '(true) && (col(1) in ["x", "y"])'
    )
  end)
end)

describe("commands.row", function()
  it("writes the row unquoted, with the ascii separators between its values", function()
    local view = fixture.duplicated_headers()
    local argv = commands.row(view, 7)

    matches(argv[3], "slice %-s 7 %-l 1")
    matches(argv[3], "behead")
    matches(argv[3], "fmt %-%-ascii %-%-quote%-never")
    lacks(argv[3], "rename")
  end)

  it("pads the record, so a single empty value does not come back quoted", function()
    local view = fixture.duplicated_headers()
    matches(commands.row(view, 0)[3], 'map .%(""%) as csv_table_padding')
  end)
end)

describe("commands.yank", function()
  it("carries the yanked columns and drops the row id at the end", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 1, 2 },
      columns = { source[1], source[3] },
      headers = true,
      format = "tsv",
    })

    matches(argv[3], "select '0,2'")
    matches(argv[3], "select '1,2'")
    matches(argv[3], "fmt %-%-tabs")
  end)

  it("takes a run of consecutive rows in one slice", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 4, 5, 6 },
      columns = { source[1] },
      headers = true,
      format = "tsv",
    })
    matches(argv[3], "slice %-s 4 %-l 3")
  end)

  it("puts scattered rows back in the order they are drawn", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 9, 2 },
      columns = { source[1] },
      headers = true,
      format = "tsv",
    })

    matches(argv[3], "slice %-I 9,2")
    matches(argv[3], '"9": 1, "2": 2')
    matches(argv[3], "sort %-s 2 %-N")
  end)

  it("beheads the output when the headers are unwanted", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 1 },
      columns = { source[1] },
      headers = false,
      format = "tsv",
    })
    matches(argv[3], "behead")
  end)

  it("writes CSV with no writer stage of its own", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 1 },
      columns = { source[1] },
      headers = true,
      format = "csv",
    })

    lacks(argv[3], "fmt")
    lacks(argv[3], "to ")
  end)

  it("names the columns by their labels for json, so a repeated header keeps both", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 1 },
      columns = { source[1], source[3] },
      headers = true,
      format = "json",
    })

    matches(argv[3], 'select %-e .col%(1%) as "a%[0%]", col%(2%) as "a%[1%]"')
    matches(argv[3], "to json")
  end)

  it("writes a markdown table", function()
    local view, source = fixture.duplicated_headers()
    local argv = commands.yank(view, {
      rowids = { 1 },
      columns = { source[1] },
      headers = true,
      format = "markdown",
    })
    matches(argv[3], "to md")
  end)
end)
