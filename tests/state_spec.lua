local fixture = require("support.fixture")
local state = require("csv-table.state")

--- A state whose rows have already been counted.
---@return csv.State
---@return csv.Column[]
local function counted()
  local view, source = fixture.duplicated_headers()
  view.row_count = 500
  return view, source
end

describe("state.row_count", function()
  it("starts unknown", function()
    local view = fixture.duplicated_headers()
    equals(view.row_count, nil)
  end)

  it("goes stale when a filter is added", function()
    local view, source = counted()
    state.add_filter(view, {
      type = "string",
      column = source[1],
      operator = "eq",
      value = "x",
    })
    equals(view.row_count, nil)
  end)

  it("goes stale when a filter is dropped", function()
    local view = counted()
    state.pop_filter(view)
    equals(view.row_count, nil)
  end)

  it("goes stale when the filters are cleared", function()
    local view = counted()
    state.clear_filters(view)
    equals(view.row_count, nil)
  end)

  it("goes stale when the marked filter is toggled", function()
    local view = counted()
    state.toggle_marked_filter(view)
    equals(view.row_count, nil)
  end)

  it("survives a sort, which reorders the same rows", function()
    local view, source = counted()
    state.sort_by(view, source[1], "asc")
    equals(view.row_count, 500)
  end)

  it("survives a mark while the view shows every row", function()
    local view = counted()
    state.toggle_mark(view, 7)
    equals(view.row_count, 500)
  end)

  it("goes stale on a mark while the marked filter is on", function()
    local view = counted()
    state.add_filter(view, { type = "marked" })
    view.row_count = 3

    state.toggle_mark(view, 7)
    equals(view.row_count, nil)
  end)

  it("goes stale when the marks are cleared under the marked filter", function()
    local view = counted()
    state.add_filter(view, { type = "marked" })
    view.row_count = 3

    state.clear_marks(view)
    equals(view.row_count, nil)
  end)

  it("goes stale on reset", function()
    local view = counted()
    state.reset(view)
    equals(view.row_count, nil)
  end)
end)

describe("state.first_row_number", function()
  it("counts on across pages", function()
    local view = fixture.duplicated_headers()
    view.limit = 1000

    equals(state.first_row_number(view), 1)
    state.turn_page(view, 1)
    equals(state.first_row_number(view), 1001)
  end)

  it("stops at the first page going back", function()
    local view = fixture.duplicated_headers()
    state.turn_page(view, -1)
    equals(view.page, 0)
  end)
end)

describe("state.add_filter", function()
  it("goes back to the first page", function()
    local view, source = fixture.duplicated_headers()
    state.turn_page(view, 3)
    state.add_filter(view, {
      type = "string",
      column = source[1],
      operator = "eq",
      value = "x",
    })
    equals(view.page, 0)
  end)
end)
