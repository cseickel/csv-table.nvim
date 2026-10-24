--[[
The `csv.View` methods that select cells by dragging the mouse.

A drag starts with a press on the cells of the window the user is already in. It
runs apart from nvim's own drag, which would enter visual mode and move the cursor
on every event. While the pointer is past the cells a window can show without
scrolling, a timer keeps stepping the selection toward it, and the farther out it
is the shorter the interval.
]]

local M = {}

--- Milliseconds between steps, near the edge and farther out. A row is shorter
--- than a column is wide, so rows step faster.
local ROW_INTERVALS = { near = 150, far = 50 }
local COLUMN_INTERVALS = { near = 300, far = 100 }

---@class csv.AutoScroll
---@field rows integer    The row step each tick takes: -1, 0 or 1.
---@field columns integer The column step each tick takes: -1, 0 or 1.
---@field interval integer
---@field timer integer
---@field mouse csv.MousePosition Where the pointer was at the last drag event.

---@class csv.ScrollNeed
---@field rows integer
---@field columns integer
---@field interval integer

---@class csv.TextArea Screen rows and columns of a window's text, 1-based.
---@field top integer
---@field bottom integer
---@field left integer
---@field right integer

--- Returns where the window's text is on screen. The winbar and the gutter, where
--- the row numbers are drawn, lie outside it.
---@return csv.TextArea
local function text_area(self)
  local info = vim.fn.getwininfo(self.window)[1]
  local top = info.winrow + info.winbar
  return {
    top = top,
    bottom = top + info.height - 1,
    left = info.wincol + info.textoff,
    right = info.wincol + info.width - 1,
  }
end

--- Returns the step on one axis toward a pointer `beyond` screen cells past the
--- edge of the strip where a scroll starts, and the interval for it. A pointer as
--- far as half the strip's width, or one cell when there is no strip, is near.
--- Returns 0 and nil for a pointer short of the strip.
---@param beyond integer Positive past the far edge, negative past the near one.
---@param band integer The strip's width.
---@param intervals { near: integer, far: integer }
---@return integer step
---@return integer|nil interval
local function axis_step(beyond, band, intervals)
  if beyond == 0 then
    return 0, nil
  end
  local near = math.abs(beyond) <= math.max(band / 2, 1)
  return beyond > 0 and 1 or -1, near and intervals.near or intervals.far
end

--- How far `value` lies past `low`..`high`, counting the first value past either end
--- as 1: negative below, positive above, 0 inside.
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

--- The width of the strip `option` keeps at each end of `low`..`high`. A window
--- too small for two strips splits its size between them.
---@param option "scrolloff"|"sidescrolloff"
---@param low integer
---@param high integer
---@return integer
local function strip(self, option, low, high)
  -- Both options are global-local, and a window with no value of its own reports -1.
  local width = vim.wo[self.window][option]
  if width < 0 then
    width = vim.go[option]
  end
  return math.min(width, math.floor((high - low) / 2))
end

--- Where the timer has to step for the pointer at `mouse`, and how often, or nil
--- when the pointer is over cells the window shows without scrolling.
---
--- The strips are the rows `scrolloff` keeps in view above and below the cursor,
--- and the columns `sidescrolloff` keeps beside it, which `csv-table.view.cursor`
--- fills with a slice of the next column. Reaching a cell in a strip scrolls it out
--- and puts another under a pointer that has not moved, so a drag there would stop
--- until the mouse moved again.
---@param mouse csv.MousePosition
---@return csv.ScrollNeed|nil
local function scroll_need(self, mouse)
  local area = text_area(self)
  local row_strip = strip(self, "scrolloff", area.top, area.bottom)
  local column_strip = strip(self, "sidescrolloff", area.left, area.right)

  local rows, row_interval = axis_step(
    past(mouse.screenrow, area.top + row_strip, area.bottom - row_strip),
    row_strip,
    ROW_INTERVALS
  )
  local columns, column_interval = axis_step(
    past(mouse.screencol, area.left + column_strip, area.right - column_strip),
    column_strip,
    COLUMN_INTERVALS
  )

  if not row_interval and not column_interval then
    return nil
  end
  return {
    rows = rows,
    columns = columns,
    interval = math.min(row_interval or math.huge, column_interval or math.huge),
  }
end

local function stop_scrolling(self)
  if self.scroll then
    vim.fn.timer_stop(self.scroll.timer)
    self.scroll = nil
  end
end

local scroll_toward

--- Step the selection one cell toward the pointer, then measure the strip again,
--- since the step can change `sidescrolloff`. A step that moves nothing has reached
--- the edge of the table, so the timer stops there and cannot outlive a release
--- nvim never delivered.
local function step(self)
  local scroll = self.scroll
  local before = self.active
  self:extend(scroll.rows, scroll.columns)
  if vim.deep_equal(before, self.active) then
    return stop_scrolling(self)
  end

  local need = scroll_need(self, scroll.mouse)
  if need then
    scroll_toward(self, need, scroll.mouse)
  else
    stop_scrolling(self)
  end
end

--- Run the timer at the interval and in the direction `need` asks for.
---@param need csv.ScrollNeed
---@param mouse csv.MousePosition
function scroll_toward(self, need, mouse)
  if self.scroll and self.scroll.interval ~= need.interval then
    stop_scrolling(self)
  end
  if self.scroll then
    self.scroll.rows, self.scroll.columns, self.scroll.mouse = need.rows, need.columns, mouse
    return
  end
  self.scroll = {
    rows = need.rows,
    columns = need.columns,
    interval = need.interval,
    mouse = mouse,
    timer = vim.fn.timer_start(need.interval, function()
      step(self)
    end, { ["repeat"] = -1 }),
  }
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

--- Take the selection to the cell under the pointer, and keep stepping it toward
--- the pointer on a timer while the pointer is in the strip or past the window.
---
--- The selection reaches the cell under the pointer first, so a fast swipe into the
--- strip lands where it points rather than one cell along. Reaching that cell can
--- change `sidescrolloff`, which is 0 on the last column, so the strip is measured
--- again after. Once a scroll is under way the timer owns the axis it steps, and
--- only the other axis follows the pointer. A pointer past the window has no cell
--- under it and takes its first step at once.
function M.drag_to_mouse(self)
  local mouse = vim.fn.getmousepos()
  local cell = self:mouse_cell(mouse)
  local need = scroll_need(self, mouse)
  local head = self:active_cell()

  if need and self.scroll then
    if cell and head then
      self:extend_to({
        row = need.rows == 0 and cell.row or head.row,
        column = need.columns == 0 and cell.column or head.column,
      })
    end
  else
    if cell then
      self:extend_to(cell)
    end
    need = scroll_need(self, mouse)
  end
  if not need then
    return stop_scrolling(self)
  end

  local starting = self.scroll == nil
  scroll_toward(self, need, mouse)
  if starting and not cell then
    step(self)
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
  local area = text_area(self)
  return past(mouse.screenrow, area.top, area.bottom) == 0
    and past(mouse.screencol, area.left, area.right) == 0
end

return M
