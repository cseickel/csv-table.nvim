local fixture = require("support.fixture")
local page = require("csv-table.page")

--- An empty page read at `version`, which is all `after_read` looks at.
---@param version string
---@return csv.Page
local function drawn(version)
  local read = page.empty()
  read.file_version = version
  return read
end

--- Settle the query against one read, then read again after `change`, so the
--- count asked for is the one that change called for.
---@param query csv.Query
---@param reader table
---@param change fun()
local function read_again(query, reader, change)
  local state = query:after_read(query:state(page.empty()), drawn("first"))
  reader.counts = 0
  change()
  query:after_read(state, drawn("first"))
end

describe("query:after_read", function()
  it("counts on the first read, where the file version arrives", function()
    local query, _, reader = fixture.duplicated_headers()
    query:after_read(query:state(page.empty()), drawn("first"))
    equals(reader.counts, 1)
  end)

  it("counts nothing when neither the file nor the filters moved", function()
    local query, _, reader = fixture.duplicated_headers()
    read_again(query, reader, function() end)
    equals(reader.counts, 0)
  end)

  it("counts when the file changed under the query", function()
    local query, _, reader = fixture.duplicated_headers()
    local state = query:after_read(query:state(page.empty()), drawn("first"))
    reader.counts = 0

    query:after_read(state, drawn("second"))
    equals(reader.counts, 1)
  end)

  it("counts when a filter is added", function()
    local query, source, reader = fixture.duplicated_headers()
    read_again(query, reader, function()
      query:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    end)
    equals(reader.counts, 1)
  end)

  it("counts when the filters are cleared", function()
    local query, source, reader = fixture.duplicated_headers()
    query:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    read_again(query, reader, function()
      query:clear_filters()
    end)
    equals(reader.counts, 1)
  end)

  it("counts nothing for a sort, which reorders the same rows", function()
    local query, source, reader = fixture.duplicated_headers()
    read_again(query, reader, function()
      query:sort_by(source[1], "asc")
    end)
    equals(reader.counts, 0)
  end)

  it("counts nothing for a page turn", function()
    local query, _, reader = fixture.duplicated_headers()
    read_again(query, reader, function()
      query:turn_page(1)
    end)
    equals(reader.counts, 0)
  end)

  it("counts on a mark while the marked filter is on", function()
    local query, _, reader = fixture.duplicated_headers()
    query:toggle_marked_filter()
    read_again(query, reader, function()
      query:toggle_mark(7)
    end)
    equals(reader.counts, 1)
  end)

  it("counts nothing for a mark while the query shows every row", function()
    local query, _, reader = fixture.duplicated_headers()
    read_again(query, reader, function()
      query:toggle_mark(7)
    end)
    equals(reader.counts, 0)
  end)

  it("holds what the reader answered", function()
    local query, _, reader = fixture.duplicated_headers()
    reader.answer = 500
    query:after_read(query:state(page.empty()), drawn("first"))
    equals(query.row_count, 500)
  end)
end)

--- Read once, then read again after `change`, and answer whether the page moved.
---@param query csv.Query
---@param change fun()
---@return boolean
local function moved_by(query, change)
  local state = query:after_read(query:state(page.empty()), drawn("first"))
  change()
  local _, moved = query:after_read(state, drawn("first"))
  return moved
end

describe("query:after_read moved", function()
  it("is false when nothing was asked of the query", function()
    local query = fixture.duplicated_headers()
    equals(
      moved_by(query, function() end),
      false
    )
  end)

  it("is true for a sort, which puts other rows between the two ends", function()
    local query, source = fixture.duplicated_headers()
    equals(
      moved_by(query, function()
        query:sort_by(source[1], "asc")
      end),
      true
    )
  end)

  it("is true for a page turn", function()
    local query = fixture.duplicated_headers()
    equals(
      moved_by(query, function()
        query:turn_page(1)
      end),
      true
    )
  end)

  it("is true for a filter", function()
    local query, source = fixture.duplicated_headers()
    equals(
      moved_by(query, function()
        query:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
      end),
      true
    )
  end)

  it("is true when a column is hidden", function()
    local query, source = fixture.duplicated_headers()
    equals(
      moved_by(query, function()
        query:hide_column(source[2])
      end),
      true
    )
  end)

  it("is false for a mark, which leaves every row where it is", function()
    local query = fixture.duplicated_headers()
    equals(
      moved_by(query, function()
        query:toggle_mark(7)
      end),
      false
    )
  end)
end)

describe("query:effective_filters", function()
  it("resolves the marked filter to the row ids marked now", function()
    local query = fixture.duplicated_headers()
    query:toggle_marked_filter()
    query:toggle_mark(7)
    query:toggle_mark(3)

    local resolved = query:effective_filters()
    equals(#resolved, 1)
    equals(resolved[1].type, "rows")
    equals(table.concat(resolved[1].row_ids, ","), "3,7")
  end)

  it("leaves every other filter as it is", function()
    local query, source = fixture.duplicated_headers()
    local filter = { type = "string", column = source[1], operator = "eq", value = "x" }
    query:add_filter(filter)
    equals(query:effective_filters()[1], filter)
  end)
end)

describe("query:first_row_number", function()
  it("counts on across pages", function()
    local query = fixture.duplicated_headers()
    query.limit = 1000

    equals(query:first_row_number(), 1)
    query:turn_page(1)
    equals(query:first_row_number(), 1001)
  end)

  it("stops at the first page going back", function()
    local query = fixture.duplicated_headers()
    query:turn_page(-1)
    equals(query.page_number, 0)
  end)
end)

describe("query:last_page", function()
  it("is the page the last row falls on", function()
    local query = fixture.duplicated_headers()
    query.limit = 100
    query.row_count = 250
    equals(query:last_page(), 2)
  end)

  it("is the first page for a file nothing has been read from", function()
    local query = fixture.duplicated_headers()
    equals(query.row_count, 0)
    equals(query:last_page(), 0)
  end)
end)

describe("query:add_filter", function()
  it("goes back to the first page", function()
    local query, source = fixture.duplicated_headers()
    query:turn_page(3)
    query:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    equals(query.page_number, 0)
  end)
end)
