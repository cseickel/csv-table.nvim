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
---@param view csv.Query
---@param reader table
---@param change fun()
local function read_again(view, reader, change)
  local state = view:after_read(view:state(page.empty()), drawn("first"))
  reader.counts = 0
  change()
  view:after_read(state, drawn("first"))
end

describe("query:after_read", function()
  it("counts on the first read, where the file version arrives", function()
    local view, _, reader = fixture.duplicated_headers()
    view:after_read(view:state(page.empty()), drawn("first"))
    equals(reader.counts, 1)
  end)

  it("counts nothing when neither the file nor the filters moved", function()
    local view, _, reader = fixture.duplicated_headers()
    read_again(view, reader, function() end)
    equals(reader.counts, 0)
  end)

  it("counts when the file changed under the query", function()
    local view, _, reader = fixture.duplicated_headers()
    local state = view:after_read(view:state(page.empty()), drawn("first"))
    reader.counts = 0

    view:after_read(state, drawn("second"))
    equals(reader.counts, 1)
  end)

  it("counts when a filter is added", function()
    local view, source, reader = fixture.duplicated_headers()
    read_again(view, reader, function()
      view:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    end)
    equals(reader.counts, 1)
  end)

  it("counts when the filters are cleared", function()
    local view, source, reader = fixture.duplicated_headers()
    view:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    read_again(view, reader, function()
      view:clear_filters()
    end)
    equals(reader.counts, 1)
  end)

  it("counts nothing for a sort, which reorders the same rows", function()
    local view, source, reader = fixture.duplicated_headers()
    read_again(view, reader, function()
      view:sort_by(source[1], "asc")
    end)
    equals(reader.counts, 0)
  end)

  it("counts nothing for a page turn", function()
    local view, _, reader = fixture.duplicated_headers()
    read_again(view, reader, function()
      view:turn_page(1)
    end)
    equals(reader.counts, 0)
  end)

  it("counts on a mark while the marked filter is on", function()
    local view, _, reader = fixture.duplicated_headers()
    view:toggle_marked_filter()
    read_again(view, reader, function()
      view:toggle_mark(7)
    end)
    equals(reader.counts, 1)
  end)

  it("counts nothing for a mark while the query shows every row", function()
    local view, _, reader = fixture.duplicated_headers()
    read_again(view, reader, function()
      view:toggle_mark(7)
    end)
    equals(reader.counts, 0)
  end)

  it("holds what the reader answered", function()
    local view, _, reader = fixture.duplicated_headers()
    reader.answer = 500
    view:after_read(view:state(page.empty()), drawn("first"))
    equals(view.row_count, 500)
  end)

  it("drops the selection, which names rows of the page being replaced", function()
    local view, source = fixture.duplicated_headers()
    local cell = { row = { row_id = 7, row_number = 1, buffer_line = 4 }, column = source[1] }
    view:select_cells(cell, cell, "cell")

    view:after_read(view:state(page.empty()), drawn("first"))
    equals(view:has_selection(), false)
  end)
end)

describe("query:effective_filters", function()
  it("resolves the marked filter to the row ids marked now", function()
    local view = fixture.duplicated_headers()
    view:toggle_marked_filter()
    view:toggle_mark(7)
    view:toggle_mark(3)

    local resolved = view:effective_filters()
    equals(#resolved, 1)
    equals(resolved[1].type, "rows")
    equals(table.concat(resolved[1].row_ids, ","), "3,7")
  end)

  it("leaves every other filter as it is", function()
    local view, source = fixture.duplicated_headers()
    local filter = { type = "string", column = source[1], operator = "eq", value = "x" }
    view:add_filter(filter)
    equals(view:effective_filters()[1], filter)
  end)
end)

describe("query:first_row_number", function()
  it("counts on across pages", function()
    local view = fixture.duplicated_headers()
    view.limit = 1000

    equals(view:first_row_number(), 1)
    view:turn_page(1)
    equals(view:first_row_number(), 1001)
  end)

  it("stops at the first page going back", function()
    local view = fixture.duplicated_headers()
    view:turn_page(-1)
    equals(view.page_number, 0)
  end)
end)

describe("query:last_page", function()
  it("is the page the last row falls on", function()
    local view = fixture.duplicated_headers()
    view.limit = 100
    view.row_count = 250
    equals(view:last_page(), 2)
  end)

  it("is the first page for a file nothing has been read from", function()
    local view = fixture.duplicated_headers()
    equals(view.row_count, 0)
    equals(view:last_page(), 0)
  end)
end)

describe("query:add_filter", function()
  it("goes back to the first page", function()
    local view, source = fixture.duplicated_headers()
    view:turn_page(3)
    view:add_filter({ type = "string", column = source[1], operator = "eq", value = "x" })
    equals(view.page_number, 0)
  end)
end)
