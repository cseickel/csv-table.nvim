--[[
View state and the actions that change it.

One state table per buffer, holding what the user asked for rather than any row
data. Every action here takes the values it needs explicitly, so it can be
called from a keymap, a command, or a test. Resolving those values from the
cursor belongs to `csv-table.buffer`.
]]

local columns = require("csv-table.columns")
local format = require("csv-table.format")

local M = {}

--- Rows a page holds in a buffer that has not been told otherwise. `setup`
--- replaces it.
M.page_size = 1000

---@class csv.SortKey
---@field column csv.Column
---@field direction "asc"|"desc"
---@field numeric boolean

---@class csv.FilterNumeric
---@field type "numeric"
---@field column csv.Column
---@field operator "=="|"!="|"<"|"<="|">"|">="
---@field value number

---@class csv.FilterString
---@field type "string"
---@field column csv.Column
---@field operator "eq"|"ne"|"contains"|"startswith"|"endswith"|"regex"
---@field value string

---@class csv.FilterIn
---@field type "in"
---@field column csv.Column
---@field values string[]

---@class csv.FilterMarked
---@field type "marked"

---@class csv.FilterExpr
---@field type "expr"
---@field expression string Hand-written moonblade.

---@alias csv.Filter csv.FilterNumeric|csv.FilterString|csv.FilterIn|csv.FilterMarked|csv.FilterExpr

---@class csv.State
---@field source string         Path of the file.
---@field sheet integer         0-based sheet being read, 0 for a source without sheets.
---@field sheets string[]       Every sheet name, empty for a source without sheets.
---@field columns csv.Column[]  Every source column, in display order, hidden ones among them.
---@field rowid_column csv.Column The prepended row id, which `layout.parse` cuts back out.
---@field row_count integer|nil How many rows the filters leave, once xan has counted them.
---@field filters csv.Filter[]  ANDed together.
---@field sort_keys csv.SortKey[] Most significant key first.
---@field clipboard csv.Column[] Cut columns waiting to be pasted.
---@field marked table<integer, boolean> Marked row ids.
---@field marked_columns table<integer, boolean> Marked column ids.
---@field selection csv.Selection|nil The cells picked out, absent when none are.
---@field columns_filtered_to_marks boolean
---@field formats table<integer, csv.Format> Keyed by column id.
---@field page integer          0-based.
---@field limit integer         Rows per page.

---@param source csv.Source
---@return csv.State
function M.new(source)
  return {
    source = source.path,
    sheet = source.sheet,
    sheets = source.sheets,
    columns = source.columns,
    -- `column_id` -1 keeps the row id clear of every source column and of
    -- `state.formats`. `csv-table.source` picks a name the file's headers leave
    -- free.
    rowid_column = {
      name = source.rowid_name,
      label = source.rowid_name,
      column_id = -1,
      hidden = false,
    },
    formats = source.formats,
    filters = {},
    sort_keys = {},
    clipboard = {},
    marked = {},
    marked_columns = {},
    columns_filtered_to_marks = false,
    page = 0,
    limit = M.page_size,
  }
end

--- Every source column in file order, which is how the stream arrives and so
--- how `rename` addresses them.
---@param state csv.State
---@return csv.Column[]
function M.source_order(state)
  local ordered = {}
  for index, column in ipairs(state.columns) do
    ordered[index] = column
  end
  table.sort(ordered, function(left, right)
    return left.column_id < right.column_id
  end)
  return ordered
end

--- Whether a column holds numbers, which decides how it sorts.
---@param state csv.State
---@param column csv.Column
---@return boolean
function M.is_numeric(state, column)
  return format.is_numeric(state.formats[column.column_id])
end

-- Sorting -------------------------------------------------------------------

--- Sort by one column alone. Asking again for the direction it already has
--- clears the sort, which is how a sort is undone.
---@param state csv.State
---@param column csv.Column
---@param direction "asc"|"desc"
function M.sort_by(state, column, direction)
  local only = #state.sort_keys == 1 and state.sort_keys[1]
  if only and only.column.column_id == column.column_id and only.direction == direction then
    state.sort_keys = {}
  else
    state.sort_keys = {
      { column = column, direction = direction, numeric = M.is_numeric(state, column) },
    }
  end
  state.page = 0
end

--- Add a less significant sort key, or change the direction of one already
--- present. Asking again for the direction it already has removes that key.
---@param state csv.State
---@param column csv.Column
---@param direction "asc"|"desc"
function M.add_sort_key(state, column, direction)
  for index, key in ipairs(state.sort_keys) do
    if key.column.column_id == column.column_id then
      if key.direction == direction then
        table.remove(state.sort_keys, index)
      else
        key.direction = direction
      end
      state.page = 0
      return
    end
  end

  table.insert(state.sort_keys, {
    column = column,
    direction = direction,
    numeric = M.is_numeric(state, column),
  })
  state.page = 0
end

---@param state csv.State
---@param column csv.Column
function M.remove_sort_key(state, column)
  for index, key in ipairs(state.sort_keys) do
    if key.column.column_id == column.column_id then
      table.remove(state.sort_keys, index)
      state.page = 0
      return
    end
  end
end

---@param state csv.State
function M.clear_sort(state)
  state.sort_keys = {}
  state.page = 0
end

-- Filters -------------------------------------------------------------------

--- Go back to the first page and forget the row count, which is what changing
--- which rows are shown costs.
---@param state csv.State
local function filters_changed(state)
  state.page = 0
  state.row_count = nil
end

---@param state csv.State
---@param filter csv.Filter
function M.add_filter(state, filter)
  table.insert(state.filters, filter)
  filters_changed(state)
end

---@param state csv.State
function M.pop_filter(state)
  table.remove(state.filters)
  filters_changed(state)
end

---@param state csv.State
function M.clear_filters(state)
  state.filters = {}
  filters_changed(state)
end

-- Marks ---------------------------------------------------------------------

--- Whether a filter is reading the marked set, which makes marking a row change
--- how many rows there are.
---@param state csv.State
---@return boolean
local function filtered_to_marks(state)
  for _, filter in ipairs(state.filters) do
    if filter.type == "marked" then
      return true
    end
  end
  return false
end

---@param state csv.State
---@param rowid integer
function M.toggle_mark(state, rowid)
  state.marked[rowid] = not state.marked[rowid] or nil
  if filtered_to_marks(state) then
    state.row_count = nil
  end
end

---@param state csv.State
function M.clear_marks(state)
  state.marked = {}
  if filtered_to_marks(state) then
    state.row_count = nil
  end
end

---@param state csv.State
---@param column csv.Column
function M.toggle_mark_column(state, column)
  state.marked_columns[column.column_id] = not state.marked_columns[column.column_id] or nil
end

---@param state csv.State
function M.clear_marked_columns(state)
  state.marked_columns = {}
end

--- Turn the marked-rows filter on, or off if it is already on.
---@param state csv.State
function M.toggle_marked_filter(state)
  for index, filter in ipairs(state.filters) do
    if filter.type == "marked" then
      table.remove(state.filters, index)
      filters_changed(state)
      return
    end
  end
  M.add_filter(state, { type = "marked" })
end

-- Paging --------------------------------------------------------------------

---@param state csv.State
---@param delta integer
function M.turn_page(state, delta)
  state.page = math.max(0, state.page + delta)
end

---@param state csv.State
---@param page integer
function M.goto_page(state, page)
  state.page = math.max(0, page)
end

--- The number the first row of the page is drawn with. Numbering runs across the
--- whole result rather than restarting on each page, so the row a user names is
--- the row they would name in a spreadsheet.
---@param state csv.State
---@return integer
function M.first_row_number(state)
  return state.page * state.limit + 1
end

---@param state csv.State
---@param size integer
function M.set_page_size(state, size)
  state.limit = math.max(1, size)
  state.page = 0
end

---@param state csv.State
function M.reset(state)
  state.filters = {}
  state.sort_keys = {}
  state.clipboard = {}
  state.marked = {}
  state.marked_columns = {}
  state.selection = nil
  state.page = 0
  state.row_count = nil
  columns.show_all(state)
end

return M
