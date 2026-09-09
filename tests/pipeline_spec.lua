local commands = require("csv-table.reader.commands")
local expression = require("csv-table.reader.expression")
local fixture = require("support.fixture")
local pipeline = require("csv-table.reader.pipeline")

--- The pipeline string for the current query, with every column on display.
---@param query csv.Query
---@return string
local function built(query)
  return pipeline.build(query, query:display_columns())
end

--- The filter expression the current query renders to.
---@param query csv.Query
---@return string
local function filters_of(query)
  local _, positions = pipeline.carried_columns(query, query:display_columns())
  return expression.all_filters(query:effective_filters(), positions)
end

describe("pipeline.carried_columns", function()
  it("lands the row id at zero and each column at its place in the list", function()
    local query = fixture.duplicated_headers()
    local carried, positions = pipeline.carried_columns(query, query:display_columns())

    equals(#carried, 3)
    equals(positions[0], 1)
    equals(positions[1], 2)
    equals(positions[2], 3)
  end)

  it("carries a hidden column that a sort key names", function()
    local query, source = fixture.duplicated_headers()
    query:hide_column(source[3])
    query:sort_by(source[3], "desc")

    local carried = pipeline.carried_columns(query, query:display_columns())
    equals(#carried, 3)
    equals(carried[3].column_id, 2)
  end)

  it("carries a hidden column that a filter names", function()
    local query, source = fixture.duplicated_headers()
    query:hide_column(source[2])
    query:add_filter({
      type = "string",
      column = source[2],
      operator = "contains",
      value = "x",
    })

    local carried = pipeline.carried_columns(query, query:display_columns())
    equals(#carried, 3)
    equals(carried[3].column_id, 1)
  end)
end)

describe("pipeline.build", function()
  it("opens by selecting the carried columns and prepending the row id", function()
    local query = fixture.duplicated_headers()
    matches(built(query), "^select '0,1,2' | enum %-c 'id'")
  end)

  it("sorts by the position the opening select fixed", function()
    local query, source = fixture.duplicated_headers()
    query:sort_by(source[3], "desc")
    matches(built(query), "sort %-s 3 %-R")
  end)

  it("sorts numerically when the column holds numbers", function()
    local query, source = fixture.duplicated_headers()
    query.file.formats[source[1].column_id] = { kind = "int", precision = 0 }
    query:sort_by(source[1], "asc")
    matches(built(query), "sort %-s 1 %-N")
  end)

  it("applies the sort keys least significant first", function()
    local query, source = fixture.duplicated_headers()
    query:sort_by(source[1], "asc")
    query:add_sort_key(source[3], "asc")

    local pipeline_string = built(query)
    local significant = pipeline_string:find("sort %-s 1")
    local minor = pipeline_string:find("sort %-s 3")
    truthy(minor < significant)
  end)

  it("slices the page the query asks for", function()
    local query = fixture.duplicated_headers()
    query.page_number = 2
    query.limit = 100
    matches(built(query), "slice %-s 200 %-l 100")
  end)

  it("closes by naming the row id and each displayed column", function()
    local query = fixture.duplicated_headers()
    matches(built(query), 'select %-e \'col%(0%) as "id"')
    matches(built(query), 'col%(1%) || " " as "a%[0%]"')
  end)

  it("leaves a hidden column out of the closing select", function()
    local query, source = fixture.duplicated_headers()
    query:hide_column(source[3])
    query:sort_by(source[3], "desc")

    local pipeline_string = built(query)
    matches(pipeline_string, "sort %-s 3")
    lacks(pipeline_string, 'as "a%[1%]')
  end)

  it("marks a sorted column in its header", function()
    local query, source = fixture.duplicated_headers()
    query:sort_by(source[1], "asc")
    matches(built(query), 'as "a%[0%] ▲"')
  end)

  it("numbers the arrows when several keys are in play", function()
    local query, source = fixture.duplicated_headers()
    query:sort_by(source[1], "asc")
    query:add_sort_key(source[3], "desc")

    local pipeline_string = built(query)
    matches(pipeline_string, 'as "a%[0%] ▲1"')
    matches(pipeline_string, 'as "a%[1%] ▼2"')
  end)

  it("cuts a header down to the width the user pinned", function()
    local query, source = fixture.duplicated_headers()
    query.file.formats[source[1].column_id] = {
      kind = "text",
      precision = 0,
      width = 3,
      align = "left",
    }
    matches(built(query), 'as "a%[…"')
  end)

  it("right aligns the numeric columns by their drawn position", function()
    local query, source = fixture.duplicated_headers()
    query.file.formats[source[2].column_id] = { kind = "float", precision = 2 }
    matches(built(query), "%-r '2'")
  end)

  it("caps a column nobody pinned at 200 characters", function()
    local query = fixture.duplicated_headers()
    matches(built(query), "%-%-cols 267")
  end)

  it("gives a pinned column the width to be drawn whole", function()
    local query, source = fixture.duplicated_headers()
    query.file.formats[source[1].column_id] = {
      kind = "text",
      precision = 0,
      width = 900,
      align = "left",
    }
    matches(built(query), "%-%-cols 1200")
  end)

  it("takes the widest pin, since the cap is per column", function()
    local query, source = fixture.duplicated_headers()
    query.file.formats[source[1].column_id] = {
      kind = "text",
      precision = 0,
      width = 900,
      align = "left",
    }
    query.file.formats[source[2].column_id] = {
      kind = "text",
      precision = 0,
      width = 300,
      align = "left",
    }
    matches(built(query), "%-%-cols 1200")
  end)
end)

describe("expression.all_filters", function()
  it("addresses a column by the position the opening select fixed", function()
    local query, source = fixture.duplicated_headers()
    query:add_filter({
      type = "string",
      column = source[3],
      operator = "contains",
      value = "x",
    })
    equals(filters_of(query), 'contains(col(3), "x")')
  end)

  it("wraps a numeric comparison so a value that fails to cast drops out", function()
    local query, source = fixture.duplicated_headers()
    query:add_filter({
      type = "numeric",
      column = source[1],
      operator = ">=",
      value = 10,
    })
    equals(filters_of(query), "try(col(1) >= 10)")
  end)

  it("reads the marked rows off the row id at zero", function()
    local query = fixture.duplicated_headers()
    query:toggle_mark(7)
    query:toggle_mark(3)
    query:add_filter({ type = "marked" })
    equals(filters_of(query), '(col(0) in ["3", "7"])')
  end)

  it("ANDs several filters together", function()
    local query, source = fixture.duplicated_headers()
    query:add_filter({ type = "expr", expression = "true" })
    query:add_filter({
      type = "in",
      column = source[1],
      values = { "x", "y" },
    })
    equals(filters_of(query), '(true) && (col(1) in ["x", "y"])')
  end)
end)

describe("commands.row", function()
  it("writes the row unquoted, with the ascii separators between its values", function()
    local query = fixture.duplicated_headers()
    local argv = commands.row(query, 7)

    matches(argv[3], "slice %-s 7 %-l 1")
    matches(argv[3], "behead")
    matches(argv[3], "fmt %-%-ascii %-%-quote%-never")
    lacks(argv[3], "rename")
  end)

  it("pads the record, so a single empty value does not come back quoted", function()
    local query = fixture.duplicated_headers()
    matches(commands.row(query, 0)[3], 'map .%(""%) as csv_table_padding')
  end)
end)

describe("commands.export", function()
  it("carries the exported columns and drops the row id at the end", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 1, 2 }, columns = { source[1], source[3] } },
      headers = true,
      format = "tsv",
    })

    matches(argv[3], "select '0,2'")
    matches(argv[3], "select '1,2'")
    matches(argv[3], "fmt %-%-tabs")
  end)

  it("takes a run of consecutive rows in one slice", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 4, 5, 6 }, columns = { source[1] } },
      headers = true,
      format = "tsv",
    })
    matches(argv[3], "slice %-s 4 %-l 3")
  end)

  it("puts scattered rows back in the order they are drawn", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 9, 2 }, columns = { source[1] } },
      headers = true,
      format = "tsv",
    })

    matches(argv[3], "slice %-I 9,2")
    matches(argv[3], '"9": 1, "2": 2')
    matches(argv[3], "sort %-s 2 %-N")
  end)

  it("beheads the output when the headers are unwanted", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 1 }, columns = { source[1] } },
      headers = false,
      format = "tsv",
    })
    matches(argv[3], "behead")
  end)

  it("writes CSV with no writer stage of its own", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 1 }, columns = { source[1] } },
      headers = true,
      format = "csv",
    })

    lacks(argv[3], "fmt")
    lacks(argv[3], "to ")
  end)

  it("names the columns by their labels for json, so a repeated header keeps both", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 1 }, columns = { source[1], source[3] } },
      headers = true,
      format = "json",
    })

    matches(argv[3], 'select %-e .col%(1%) as "a%[0%]", col%(2%) as "a%[1%]"')
    matches(argv[3], "to json")
  end)

  it("writes a markdown table", function()
    local query, source = fixture.duplicated_headers()
    local argv = commands.export(query, {
      block = { row_ids = { 1 }, columns = { source[1] } },
      headers = true,
      format = "markdown",
    })
    matches(argv[3], "to md")
  end)
end)
