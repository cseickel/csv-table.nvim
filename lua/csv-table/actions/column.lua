--[[
The actions that act on a column.

Hiding, cutting, pasting and moving change which columns are shown. Aligning,
padding and formatting change how one column reads. Both resolve their column
from the cursor, and the movement ones carry the cursor along so the column that
moved is still the one under it.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local format = require("csv-table.format")
local selection = require("csv-table.selection")
local utils = require("csv-table.actions.utils")

--- Repaint, then put the cursor at the start of `column`, so a column that
--- changed stays under the cursor that changed it. A narrowing column would
--- otherwise slide out from under the cursor, and the next key would act on
--- whichever column the cursor had been left over.
---@param buf csv.Buffer
---@param column csv.Column
---@param on_focused fun(cell: integer)|nil Runs once the cursor is back on the column.
local function follow(buf, column, on_focused)
  local position = selection.position(buf.state, column)

  buffer.render(buf, function()
    if not position then
      return
    end
    cursor.focus_cell(buf, 0, position + 1)
    if on_focused then
      on_focused(position + 1)
    end
  end)
end

--- A column that moved is somewhere else on the line, so it flashes to be found
--- again. A column that only changed width has not gone anywhere.
---@param buf csv.Buffer
---@return fun(cell: integer)
local function flash(buf)
  return function(cell)
    cursor.flash_cell(buf, cell)
  end
end

--- Change how the column under the cursor is padded, measuring the column as it
--- is drawn so the change starts from the width on screen.
---@param buf csv.Buffer
---@param change fun(column: csv.Column, width: integer)
local function on_padding(buf, change)
  local column = utils.column_under_cursor(buf)
  if not column then
    return
  end

  local painted = buffer.column_width(buf, column)
  if not painted then
    return
  end
  change(column, format.working_width(buf.state.formats, column, painted))
  follow(buf, column)
end

---@param align "left"|"center"|"right"
---@return fun(buf: csv.Buffer)
local function aligner(align)
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
local function mover(delta)
  return function(buf)
    local column = cursor.column_at(buf, 0)
    if column and selection.swap_column(buf.state, column, delta) then
      follow(buf, column, flash(buf))
    end
  end
end

---@param before boolean
---@return fun(buf: csv.Buffer)
local function paster(before)
  return function(buf)
    local held = buf.state.clipboard[1]
    local column = cursor.column_at(buf, 0)
    if selection.paste_columns(buf.state, column, before) then
      follow(buf, held, flash(buf))
    end
  end
end

utils.register_action("next_column", "Move to the next column", function(buf)
  cursor.jump_column(buf, 0, 1)
end)

utils.register_action("prev_column", "Move to the previous column", function(buf)
  cursor.jump_column(buf, 0, -1)
end)

utils.register_action("hide_column", "Hide this column", function(buf)
  utils.on_column(buf, function(column)
    selection.hide_column(buf.state, column)
  end)
end)

utils.register_action("show_all_columns", "Show every column again", function(buf)
  selection.show_all_columns(buf.state)
  buffer.render(buf)
end)

utils.register_action("cut_column", "Cut this column, holding it to paste", function(buf)
  utils.on_column(buf, function(column)
    selection.cut_column(buf.state, column, false)
  end)
end)

utils.register_action("cut_append_column", "Add this column to the cut being held", function(buf)
  utils.on_column(buf, function(column)
    selection.cut_column(buf.state, column, true)
  end)
end)

utils.register_action("paste_columns_after", "Paste the held columns after this one", paster(false))
utils.register_action("paste_columns_before", "Paste the held columns before this one", paster(true))
utils.register_action("move_column_left", "Move this column one place left", mover(-1))
utils.register_action("move_column_right", "Move this column one place right", mover(1))

utils.register_action("align_left", "Align this column left", aligner("left"))
utils.register_action("align_center", "Align this column centre", aligner("center"))
utils.register_action("align_right", "Align this column right", aligner("right"))

utils.register_action("increase_precision", "Show one more decimal in this column", precision(1))
utils.register_action("decrease_precision", "Show one fewer decimal in this column", precision(-1))
utils.register_action("increase_width", "Widen this column by one", width(1))
utils.register_action("decrease_width", "Narrow this column by one", width(-1))

utils.register_action("set_format", "Give this column a printf format", function(buf)
  local column = utils.column_under_cursor(buf)
  if not column then
    return
  end

  local current = buf.state.formats[column.index]
  vim.ui.input({ prompt = "printf format: ", default = current and current.spec or "" }, function(spec)
    if spec == nil then
      return
    end
    format.set_spec(buf.state.formats, column, spec)
    buffer.render(buf)
  end)
end)
