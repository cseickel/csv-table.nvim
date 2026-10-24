--[[
The `csv.View` methods that select cells by dragging the mouse.

A drag starts with a press on the cells of the window the user is already in. It
runs apart from nvim's own drag, which would enter visual mode and move the cursor
on every event. While the pointer is outside the cells a timer keeps stepping the
selection toward it, and the farther out it is the shorter the interval.
]]

local M = {}

--- Milliseconds between steps with the pointer one screen cell outside the cells,
--- and with it two or more cells outside.
local NEAR_INTERVAL = 300
local FAR_INTERVAL = 100

---@class csv.AutoScroll
---@field rows integer    The row step each tick takes: -1, 0 or 1.
---@field columns integer The column step each tick takes: -1, 0 or 1.
---@field interval integer
---@field timer integer

--- How far `value` lies outside `low`..`high`: negative below, positive above, 0
--- inside.
---@param value integer
---@param low integer
---@param high integer
---@return integer
local function past(value, low, high)
  if value < low then
    return value - low
  end
  if value > high then
    return value - high
  end
  return 0
end

---@param value integer
---@return integer
local function sign(value)
  if value < 0 then
    return -1
  end
  return value > 0 and 1 or 0
end

--- How many screen rows and columns the pointer is outside the window's text,
--- negative above it and to its left. The winbar and the gutter count as outside.
---@param mouse csv.MousePosition
---@return integer rows
---@return integer columns
local function outside_text(self, mouse)
  local info = vim.fn.getwininfo(self.window)[1]
  local top = info.winrow + info.winbar
  local left = info.wincol + info.textoff
  return past(mouse.screenrow, top, top + info.height - 1),
    past(mouse.screencol, left, info.wincol + info.width - 1)
end

local function stop_scrolling(self)
  if self.scroll then
    vim.fn.timer_stop(self.scroll.timer)
    self.scroll = nil
  end
end

--- Step the selection one cell toward the pointer. A step that moves nothing has
--- reached the edge of the table, so the timer stops there and cannot outlive a
--- release nvim never delivered.
local function step(self)
  local before = self.active
  self:extend(self.scroll.rows, self.scroll.columns)
  if vim.deep_equal(before, self.active) then
    stop_scrolling(self)
  end
end

--- Keep stepping toward a pointer `rows` and `columns` outside the cells. A pointer
--- that has just left the cells takes its first step at once.
---@param rows integer
---@param columns integer
local function scroll_toward(self, rows, columns)
  local distance = math.max(math.abs(rows), math.abs(columns))
  local interval = distance >= 2 and FAR_INTERVAL or NEAR_INTERVAL
  local just_left = self.scroll == nil

  if self.scroll and self.scroll.interval ~= interval then
    stop_scrolling(self)
  end
  if self.scroll then
    self.scroll.rows, self.scroll.columns = sign(rows), sign(columns)
  else
    self.scroll = {
      rows = sign(rows),
      columns = sign(columns),
      interval = interval,
      timer = vim.fn.timer_start(interval, function()
        step(self)
      end, { ["repeat"] = -1 }),
    }
  end

  if just_left then
    step(self)
  end
end

--- Start a drag on the cell under the pointer, once nvim's own click has moved the
--- cursor there. A press off the cells, on a status line or a separator, starts
--- none, which leaves the drag after it to nvim for resizing windows.
function M.press(self)
  self:release()
  local cell = self:mouse_cell(vim.fn.getmousepos())
  if not cell then
    return
  end
  self:deselect()
  self:go_to(cell)
  self.dragging = true
end

--- Take the selection to the cell under the pointer, or toward the pointer on a
--- timer while it is outside the cells.
function M.drag_to_mouse(self)
  local mouse = vim.fn.getmousepos()
  local rows, columns = outside_text(self, mouse)
  if rows ~= 0 or columns ~= 0 then
    return scroll_toward(self, rows, columns)
  end

  stop_scrolling(self)
  local cell = self:mouse_cell(mouse)
  if cell then
    self:extend_to(cell)
  end
end

function M.release(self)
  stop_scrolling(self)
  self.dragging = false
end

--- Whether the pointer is over this window's text.
---@param mouse csv.MousePosition
---@return boolean
function M.over_text(self, mouse)
  local rows, columns = outside_text(self, mouse)
  return rows == 0 and columns == 0
end

return M
