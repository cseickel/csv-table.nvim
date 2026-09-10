--[[
Defines `csv.View`, one window's view of one table: the cell the user is on, the
cells picked out, and where the window is scrolled to.

A buffer holds one view per window showing it, handed out by `Buffer:view`. Every
cell is held as a `csv.CellRef` and resolved against the page drawn now, so a
sort or a filter that keeps a row takes the view with it.

The active cell and the selection are drawn into one namespace on the buffer,
which the window the user is in holds.
]]

local M = {}

local namespace = vim.api.nvim_create_namespace("csv-view")

-- Above the marked rows, the marked columns and the flash, which take nvim's
-- default of 4096.
local SELECTION_PRIORITY = 4200
local CELL_PRIORITY = 4300

---@class csv.View
---@field buffer csv.Buffer
---@field window integer
---@field active csv.CellRef|nil Where the user is, absent until the first render.
---@field position integer[] Line and byte column, as nvim reports a cursor.
---@field edge "left"|"right" Which end of the active cell the cursor is parked at.
---@field anchor csv.CellRef|nil Where selecting started.
---@field head csv.CellRef|nil Where the active cell was at the last extend.
---@field kind csv.SelectionKind
---@field viewport table|nil What `winsaveview` last gave for this window.
---@field clicked boolean Whether the move being handled came from the mouse.
local View = {}
View.__index = View

for _, part in ipairs({
  "csv-table.view.cursor",
  "csv-table.view.export",
  "csv-table.view.movement",
  "csv-table.view.selection",
  "csv-table.view.visual",
}) do
  for name, method in pairs(require(part)) do
    if View[name] then
      error("csv-table: two view modules define " .. name)
    end
    View[name] = method
  end
end

---@param buffer csv.Buffer
---@param window integer
---@return csv.View
function M.new(buffer, window)
  return setmetatable({
    buffer = buffer,
    window = window,
    position = { 1, 0 },
    edge = "left",
    kind = "cell",
    clicked = false,
  }, View)
end

--- A copy of this view for `window`, which is what a second window on the same
--- table starts from.
---@param window integer
---@return csv.View
function View:clone(window)
  local made = M.new(self.buffer, window)
  made.active = self.active and vim.deepcopy(self.active)
  made.position = vim.deepcopy(self.position)
  made.edge = self.edge
  made.anchor = self.anchor and vim.deepcopy(self.anchor)
  made.head = self.head and vim.deepcopy(self.head)
  made.kind = self.kind
  made.viewport = self.viewport and vim.deepcopy(self.viewport)
  return made
end

--- Whether the window still shows this table, which is what says the view is
--- taken rather than free for the next window to adopt.
---@return boolean
function View:on_screen()
  return vim.api.nvim_win_is_valid(self.window)
    and vim.api.nvim_win_get_buf(self.window) == self.buffer.bufnr
end

---@return boolean
function View:is_current()
  return self.window == vim.api.nvim_get_current_win()
end

--- The cell the user is on, which is the one drawn in `CsvActiveCell` and the one
--- every action runs on.
---@return csv.Cell|nil
function View:active_cell()
  return self.buffer.page:cell_of(self.active)
end

---@return csv.Column|nil
function View:column()
  local cell = self:active_cell()
  return cell and cell.column or nil
end

---@param cell csv.Cell
local function extmark(self, cell, group, priority)
  local page = self.buffer.page
  local column_number = page:column_number(cell.column)
  if not column_number then
    return
  end
  local from, to = page:cell_bounds(cell.row.buffer_line, column_number)
  if from then
    vim.api.nvim_buf_set_extmark(self.buffer.bufnr, namespace, cell.row.buffer_line - 1, from, {
      end_col = to,
      hl_group = group,
      priority = priority,
    })
  end
end

--- Draw the selected cells and the active cell. One namespace on the buffer holds
--- both, so only the window the user is in can show them.
function View:draw()
  if not self:is_current() then
    return
  end

  vim.api.nvim_buf_clear_namespace(self.buffer.bufnr, namespace, 0, -1)

  local bounds = self:bounds()
  if bounds then
    for line = bounds.top, bounds.bottom do
      local cells = self.buffer.page:cell_ranges(line)
      local first, last = cells[bounds.left], cells[bounds.right]
      if first and last then
        vim.api.nvim_buf_set_extmark(self.buffer.bufnr, namespace, line - 1, first.from, {
          end_col = last.to,
          hl_group = "CsvSelection",
          priority = SELECTION_PRIORITY,
        })
      end
    end
  end

  local cell = self:active_cell()
  if cell then
    extmark(self, cell, "CsvActiveCell", CELL_PRIORITY)
  end
end

--- Keep where the window is looking, so a buffer emptied and filled again comes
--- back the way the user left it.
function View:remember()
  if self:on_screen() then
    self.viewport = vim.api.nvim_win_call(self.window, vim.fn.winsaveview)
  end
end

--- Look at the table the way this window was left. Scheduled, because `:edit`
--- puts the cursor on line 1 once the read command it fired has returned, and
--- this has to land after that.
function View:restore_viewport()
  local viewport = self.viewport
  vim.schedule(function()
    if not self:on_screen() then
      return
    end
    self:restore()
    if viewport then
      vim.api.nvim_win_call(self.window, function()
        vim.fn.winrestview(viewport)
      end)
    end
  end)
end

return M
