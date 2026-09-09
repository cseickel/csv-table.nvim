--[[
Registers the actions on the column the active cell is in: hiding, cutting and
pasting, moving, aligning, precision, width and a printf format.

An action that moves a column takes the active cell with it, so the column that
moved is still the one under the cursor.
]]

local color = require("csv-table.buffer.color")
local utils = require("csv-table.actions.utils")

--- Render, then make `column` active again, so the column the user just changed
--- stays the one they are on. A column that narrows leaves the byte the cursor is
--- parked on inside whichever column took its place, and the next key would act on
--- that one.
---@param view csv.View
---@param column csv.Column
---@param on_focused fun(column: csv.Column)|nil Runs once the column is active again.
local function follow(view, column, on_focused)
  view.buffer:render(function()
    local cell = view:active_cell()
    if not cell or not view.buffer.page:column_number(column) then
      return
    end
    view:move_to({ row = cell.row, column = column })
    if on_focused then
      on_focused(column)
    end
  end)
end

--- A column that moved is somewhere else on the line, so it flashes to be found
--- again. The width and format actions leave it where it was, and pass this by.
---@param view csv.View
---@return fun(column: csv.Column)
local function flash(view)
  return function(column)
    color.flash_column(view.buffer, column)
  end
end

--- Change how the active cell's column is padded, measuring the column as it is
--- drawn so the change starts from the width on screen.
---@param view csv.View
---@param change fun(column: csv.Column, width: integer)
local function on_padding(view, change)
  local column = view:column()
  if not column then
    return
  end

  local drawn_width = view.buffer:column_width(column)
  if not drawn_width then
    return
  end
  change(column, view.buffer.query.file:working_width(column, drawn_width))
  follow(view, column)
end

---@param align "left"|"center"|"right"
---@return fun(view: csv.View)
local function align_action(align)
  return function(view)
    on_padding(view, function(column, width)
      view.buffer.query.file:set_padding(column, { width = width, align = align })
    end)
  end
end

---@param delta integer
---@return fun(view: csv.View)
local function precision(delta)
  return function(view)
    utils.on_column(view, function(column)
      view.buffer.query.file:adjust_precision(column, delta)
    end)
  end
end

---@param delta integer
---@return fun(view: csv.View)
local function width(delta)
  return function(view)
    on_padding(view, function(column, current)
      view.buffer.query.file:set_padding(column, { width = current + delta })
    end)
  end
end

---@param delta integer
---@return fun(view: csv.View)
local function move_action(delta)
  return function(view)
    local column = view:column()
    if column and view.buffer.query:swap_columns(column, delta) then
      follow(view, column, flash(view))
    end
  end
end

---@param before boolean
---@return fun(view: csv.View)
local function paste_action(before)
  return function(view)
    local first_cut = view.buffer.query.clipboard[1]
    local column = view:column()
    if view.buffer.query:paste_columns(column, before) then
      follow(view, first_cut, flash(view))
    end
  end
end

utils.register_action("hide_column", "Hide this column", function(view)
  utils.on_column(view, function(column)
    view.buffer.query:hide_column(column)
  end)
end)

utils.register_action("show_all_columns", "Show every column again", function(view)
  view.buffer.query:show_all_columns()
  view.buffer:render()
end)

utils.register_action("cut_column", "Cut this column, keeping it to paste", function(view)
  utils.on_column(view, function(column)
    view.buffer.query:cut_column(column, false)
  end)
end)

utils.register_action("cut_append_column", "Add this column to the cut", function(view)
  utils.on_column(view, function(column)
    view.buffer.query:cut_column(column, true)
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

utils.register_action("set_format", "Give this column a printf format", function(view)
  local column = view:column()
  if not column then
    return
  end

  local file = view.buffer.query.file
  local current = file.formats[column.column_id]
  vim.ui.input({ prompt = "printf format: ", default = current and current.spec or "" }, function(spec)
    if spec == nil then
      return
    end
    file:set_spec(column, spec)
    view.buffer:render()
  end)
end)
