--[[
Registers the actions on the column the active cell is in: hiding, cutting and
pasting, moving, aligning, precision, width and a printf format.

An action that moves a column takes the active cell with it, so the column that
moved is still the one under the cursor.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.buffer.cursor")
local utils = require("csv-table.actions.utils")

--- Render, then make `column` active again, so the column the user just changed
--- stays the one they are on. A column that narrows leaves the byte the cursor is
--- parked on inside whichever column took its place, and the next key would act
--- on that one.
---@param buf csv.Buffer
---@param column csv.Column
---@param on_focused fun(column: csv.Column)|nil Runs once the column is active again.
local function follow(buf, column, on_focused)
  buffer.render(buf, function()
    local cell = cursor.cell(buf, 0)
    if not cell or not buf.page:column_number(column) then
      return
    end
    cursor.move_to(buf, 0, { row = cell.row, column = column })
    if on_focused then
      on_focused(column)
    end
  end)
end

--- A column that moved is somewhere else on the line, so it flashes to be found
--- again. The width and format actions leave it where it was, and pass this by.
---@param buf csv.Buffer
---@return fun(column: csv.Column)
local function flash(buf)
  return function(column)
    cursor.flash_column(buf, column)
  end
end

--- Change how the active cell's column is padded, measuring the column as it is
--- drawn so the change starts from the width on screen.
---@param buf csv.Buffer
---@param change fun(column: csv.Column, width: integer)
local function on_padding(buf, change)
  local column = cursor.column(buf, 0)
  if not column then
    return
  end

  local drawn_width = buffer.column_width(buf, column)
  if not drawn_width then
    return
  end
  change(column, buf.query.file:working_width(column, drawn_width))
  follow(buf, column)
end

---@param align "left"|"center"|"right"
---@return fun(buf: csv.Buffer)
local function align_action(align)
  return function(buf)
    on_padding(buf, function(column, width)
      buf.query.file:set_padding(column, { width = width, align = align })
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function precision(delta)
  return function(buf)
    utils.on_column(buf, function(column)
      buf.query.file:adjust_precision(column, delta)
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function width(delta)
  return function(buf)
    on_padding(buf, function(column, current)
      buf.query.file:set_padding(column, { width = current + delta })
    end)
  end
end

---@param delta integer
---@return fun(buf: csv.Buffer)
local function move_action(delta)
  return function(buf)
    local column = cursor.column(buf, 0)
    if column and buf.query:swap_columns(column, delta) then
      follow(buf, column, flash(buf))
    end
  end
end

---@param before boolean
---@return fun(buf: csv.Buffer)
local function paste_action(before)
  return function(buf)
    local first_cut = buf.query.clipboard[1]
    local column = cursor.column(buf, 0)
    if buf.query:paste_columns(column, before) then
      follow(buf, first_cut, flash(buf))
    end
  end
end

utils.register_action("hide_column", "Hide this column", function(buf)
  utils.on_column(buf, function(column)
    buf.query:hide_column(column)
  end)
end)

utils.register_action("show_all_columns", "Show every column again", function(buf)
  buf.query:show_all_columns()
  buffer.render(buf)
end)

utils.register_action("cut_column", "Cut this column, keeping it to paste", function(buf)
  utils.on_column(buf, function(column)
    buf.query:cut_column(column, false)
  end)
end)

utils.register_action("cut_append_column", "Add this column to the cut", function(buf)
  utils.on_column(buf, function(column)
    buf.query:cut_column(column, true)
  end)
end)

utils.register_action(
  "paste_columns_after",
  "Paste the cut columns after this one",
  paste_action(false)
)
utils.register_action(
  "paste_columns_before",
  "Paste the cut columns before this one",
  paste_action(true)
)
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
  local column = cursor.column(buf, 0)
  if not column then
    return
  end

  local current = buf.query.file.formats[column.column_id]
  vim.ui.input({ prompt = "printf format: ", default = current and current.spec or "" }, function(spec)
    if spec == nil then
      return
    end
    buf.query.file:set_spec(column, spec)
    buffer.render(buf)
  end)
end)
