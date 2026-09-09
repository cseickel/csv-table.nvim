--[[
Defines `csv.Query`, everything the user has asked of one file: which rows to
keep, in what order, which columns to draw, and which page of the result.

A query holds the file it reads and the reader that runs it, so it answers its
own row count. `after_read` is where a completed table read decides what has to
follow it, comparing the query the last page was drawn for against this one.
]]

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

---@class csv.FilterRows What a marked filter resolves to before a run.
---@field type "rows"
---@field row_ids integer[]

---@class csv.FilterExpr
---@field type "expr"
---@field expression string Hand-written moonblade.

---@alias csv.Filter csv.FilterNumeric|csv.FilterString|csv.FilterIn|csv.FilterMarked|csv.FilterRows|csv.FilterExpr

--- What a completed table read was made for. `after_read` compares one of these
--- against the query as it stands now.
---@class csv.QueryState
---@field filters csv.Filter[]
---@field file_version string

---@class csv.Query
---@field file csv.File
---@field reader csv.Reader
---@field on_changed fun() Runs when a value the statusline shows is refreshed.
---@field columns csv.Column[] Every column in display order, hidden ones among them.
---@field filters csv.Filter[] ANDed together.
---@field sort_keys csv.SortKey[] Most significant key first.
---@field clipboard csv.Column[] Cut columns waiting to be pasted.
---@field marked table<integer, boolean> Marked row ids.
---@field marked_columns table<integer, boolean> Marked column ids.
---@field columns_filtered_to_marks boolean
---@field selection csv.Selection|nil The cells picked out, absent when none are.
---@field page_number integer 0-based.
---@field limit integer Rows per page.
---@field row_count integer How many rows the filters leave.
local Query = {}
Query.__index = Query

for _, part in ipairs({ "csv-table.query.columns", "csv-table.query.selection" }) do
  for name, method in pairs(require(part)) do
    Query[name] = method
  end
end

--- A query over `file`, asking for nothing but the first page.
---@param file csv.File
---@param reader csv.Reader
---@param on_changed fun()
---@return csv.Query
function M.new(file, reader, on_changed)
  local display = {}
  for index, column in ipairs(file.columns) do
    display[index] = column
  end

  return setmetatable({
    file = file,
    reader = reader,
    on_changed = on_changed,
    columns = display,
    filters = {},
    sort_keys = {},
    clipboard = {},
    marked = {},
    marked_columns = {},
    columns_filtered_to_marks = false,
    selection = nil,
    page_number = 0,
    limit = M.page_size,
    row_count = 0,
  }, Query)
end

--- The filters as the reader runs them, with the marked filter resolved to the
--- row ids marked now. Two queries whose effective filters match leave the same
--- rows.
---@return csv.Filter[]
function Query:effective_filters()
  local resolved = {}
  for index, filter in ipairs(self.filters) do
    if filter.type == "marked" then
      local row_ids = {}
      for row_id in pairs(self.marked) do
        table.insert(row_ids, row_id)
      end
      table.sort(row_ids)
      resolved[index] = { type = "rows", row_ids = row_ids }
    else
      resolved[index] = filter
    end
  end
  return resolved
end

--- What a page drawn now would have been read for.
---@param page csv.Page
---@return csv.QueryState
function Query:state(page)
  return { filters = self:effective_filters(), file_version = page.file_version }
end

--- Count the rows the filters leave.
function Query:count()
  self.reader:count(self, function(count)
    self.row_count = count
    self.on_changed()
  end)
end

--- Decide what a completed table read calls for, given the query the page before
--- it was read for.
---@param previous csv.QueryState
---@param page csv.Page
---@return csv.QueryState
function Query:after_read(previous, page)
  local current = self:state(page)

  -- Both ends of a selection name rows and columns of the page being replaced.
  self:clear_selection()

  if
    previous.file_version ~= current.file_version
    or not vim.deep_equal(previous.filters, current.filters)
  then
    self:count()
  end

  return current
end

---@param column csv.Column
---@return boolean
function Query:is_numeric(column)
  return self.file:is_numeric(column)
end

-- Sorting ---------------------------------------------------------------------

--- Sort by one column alone. Asking again for the direction it already has clears
--- the sort, which is how a sort is undone.
---@param column csv.Column
---@param direction "asc"|"desc"
function Query:sort_by(column, direction)
  local only = #self.sort_keys == 1 and self.sort_keys[1]
  if only and only.column.column_id == column.column_id and only.direction == direction then
    self.sort_keys = {}
  else
    self.sort_keys = {
      { column = column, direction = direction, numeric = self:is_numeric(column) },
    }
  end
  self.page_number = 0
end

--- Add a less significant sort key, or change the direction of one already
--- present. Asking again for the direction it already has removes that key.
---@param column csv.Column
---@param direction "asc"|"desc"
function Query:add_sort_key(column, direction)
  for index, key in ipairs(self.sort_keys) do
    if key.column.column_id == column.column_id then
      if key.direction == direction then
        table.remove(self.sort_keys, index)
      else
        key.direction = direction
      end
      self.page_number = 0
      return
    end
  end

  table.insert(self.sort_keys, {
    column = column,
    direction = direction,
    numeric = self:is_numeric(column),
  })
  self.page_number = 0
end

---@param column csv.Column
function Query:remove_sort_key(column)
  for index, key in ipairs(self.sort_keys) do
    if key.column.column_id == column.column_id then
      table.remove(self.sort_keys, index)
      self.page_number = 0
      return
    end
  end
end

function Query:clear_sort()
  self.sort_keys = {}
  self.page_number = 0
end

-- Filters ---------------------------------------------------------------------

---@param filter csv.Filter
function Query:add_filter(filter)
  table.insert(self.filters, filter)
  self.page_number = 0
end

function Query:pop_filter()
  table.remove(self.filters)
  self.page_number = 0
end

function Query:clear_filters()
  self.filters = {}
  self.page_number = 0
end

--- Turn the marked-rows filter on, or off if it is already on.
function Query:toggle_marked_filter()
  for index, filter in ipairs(self.filters) do
    if filter.type == "marked" then
      table.remove(self.filters, index)
      self.page_number = 0
      return
    end
  end
  self:add_filter({ type = "marked" })
end

-- Marks -----------------------------------------------------------------------

---@param row_id integer
function Query:toggle_mark(row_id)
  self.marked[row_id] = not self.marked[row_id] or nil
end

function Query:clear_marks()
  self.marked = {}
end

---@param column csv.Column
function Query:toggle_mark_column(column)
  self.marked_columns[column.column_id] = not self.marked_columns[column.column_id] or nil
end

function Query:clear_marked_columns()
  self.marked_columns = {}
end

-- Paging ----------------------------------------------------------------------

---@param delta integer
function Query:turn_page(delta)
  self.page_number = math.max(0, self.page_number + delta)
end

---@param page_number integer
function Query:goto_page(page_number)
  self.page_number = math.max(0, page_number)
end

--- The 0-based number of the last page.
---@return integer
function Query:last_page()
  return math.max(math.ceil(self.row_count / self.limit) - 1, 0)
end

--- The number the first row of the page is drawn with. Numbering runs across the
--- whole result rather than restarting on each page, so the row a user names is
--- the row they would name in a spreadsheet.
---@return integer
function Query:first_row_number()
  return self.page_number * self.limit + 1
end

---@param size integer
function Query:set_page_size(size)
  self.limit = math.max(1, size)
  self.page_number = 0
end

--- Drop everything the user has asked for, keeping the file.
function Query:reset()
  self.filters = {}
  self.sort_keys = {}
  self.clipboard = {}
  self.marked = {}
  self.marked_columns = {}
  self.selection = nil
  self.page_number = 0
  self:show_all_columns()
end

return M
