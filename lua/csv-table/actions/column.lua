--[[
The actions that act on a column.

Hiding, cutting, pasting and moving change which columns are shown. Aligning,
padding and formatting change how one column reads. Both resolve their column
from the cursor, and the movement ones move the cursor too, so the column that
moved is still the one under it.
]]

local buffer = require("csv-table.buffer")
local active_cell = require("csv-table.active_cell")
local columns = require("csv-table.columns")
local format = require("csv-table.format")
local layout_module = require("csv-table.layout")
local utils = require("csv-table.actions.utils")

--- Render, then put the cursor at the start of `column`, so a column that
--- changed stays under the cursor that changed it. A narrowing column would
--- otherwise slide out from under the cursor, and the next key would act on
--- whichever column the cursor had been left over.
---@param buf csv.Buffer
---@param column csv.Column
---@param on_focused fun(column: csv.Column)|nil Runs once the cursor is back on the column.
local function follow(buf, column, on_focused)
  buffer.render(buf, function()
    local cell = active_cell.cell(buf, 0)
    if not cell or not layout_module.column_number(buf.layout, column) then
      return
    end
    active_cell.move_to(buf, 0, { row = cell.row, column = column })
    if on_focused then
      on_focused(column)
    end
  end)
end

--- A column that moved is somewhere else on the line, so it flashes to be found
--- again. A column that only changed width has not gone anywhere.
---@param buf csv.Buffer
---@return fun(column: csv.Column)
local function flash(buf)
  return function(column)
    active_cell.flash_column(buf, column)
  end
end

--- Change how the column under the cursor is padded, measuring the column as it
--- is drawn so the change starts from the width on screen.
---@param buf csv.Buffer
---@param change fun(column: csv.Column, width: integer)
local function on_padding(buf, change)
  local column = active_cell.column(buf, 0)
  if not column then
    return
  end

  local drawn_width = buffer.column_width(buf, column)
  if not drawn_width then
    return
  end
  change(column, format.working_width(buf.state.formats, column, drawn_width))
  follow(buf, column)
end

---@param align "left"|"center"|"right"
---@return fun(buf: csv.Buffer)
local function align_action(align)
  return function(buf)
    on_padding(buf, function(column, width)
      format.set_padding(buf.state.formats, column, { width = width, align = align })
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function precision(delta)
  return function(buf)
    utils.on_column(buf, function(column)
      format.adjust_precision(buf.state.formats, column, delta)
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function width(delta)
  return function(buf)
    on_padding(buf, function(column, current)
      format.set_padding(buf.state.formats, column, { width = current + delta })
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function move_action(delta)
  return function(buf)
    local column = active_cell.column(buf, 0)
    if column and columns.swap(buf.state, column, delta) then
      follow(buf, column, flash(buf))
    end
  end
end

---@param before boolean
---@return fun(buf: csv.Buffer)
local function paste_action(before)
  return function(buf)
    local first_cut = buf.state.clipboard[1]
    local column = active_cell.column(buf, 0)
    if columns.paste(buf.state, column, before) then
      follow(buf, first_cut, flash(buf))
    end
  end
end

utils.register_action("hide_column", "Hide this column", function(buf)
  utils.on_column(buf, columns.hide)
end)

utils.register_action("show_all_columns", "Show every column again", function(buf)
  columns.show_all(buf.state)
  buffer.render(buf)
end)

utils.register_action("cut_column", "Cut this column, keeping it to paste", function(buf)
  utils.on_column(buf, function(column)
    columns.cut(buf.state, column, false)
  end)
end)

utils.register_action("cut_append_column", "Add this column to the cut", function(buf)
  utils.on_column(buf, function(column)
    columns.cut(buf.state, column, true)
  end)
end)

utils.register_action("paste_columns_after", "Paste the cut columns after this one", paste_action(false))
utils.register_action("paste_columns_before", "Paste the cut columns before this one", paste_action(true))
utils.register_action("move_column_left", "Move this column one place left", move_action(-1))
utils.register_action("move_column_right", "Move this column one place right", move_action(1))

utils.register_action("align_left", "Align this column left", align_action("left"))
utils.register_action("align_center", "Align this column center", align_action("center"))
utils.register_action("align_right", "Align this column right", align_action("right"))

utils.register_action("increase_precision", "Show one more decimal in this column", precision(1))
utils.register_action("decrease_precision", "Show one fewer decimal in this column", precision(-1))
utils.register_action("increase_width", "Widen this column by one", width(1))
utils.register_action("decrease_width", "Narrow this column by one", width(-1))

utils.register_action("set_format", "Give this column a printf format", function(buf)
  local column = active_cell.column(buf, 0)
  if not column then
    return
  end

  local current = buf.state.formats[column.column_id]
  vim.ui.input({ prompt = "printf format: ", default = current and current.spec or "" }, function(spec)
    if spec == nil then
      return
    end
    format.set_spec(buf.state.formats, column, spec)
    buffer.render(buf)
  end)
end)
