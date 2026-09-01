--[[
The utils.actions that act on a column.

Hiding, cutting, pasting and moving change which columns are shown. Aligning,
padding and formatting change how one column reads. Both resolve their column
from the cursor, and the movement ones carry the cursor along so the column that
moved is still the one under it.
]]

local buffer = require("csv-table.buffer")
local cursor = require("csv-table.cursor")
local format = require("csv-table.format")
local query = require("csv-table.query")
local selection = require("csv-table.selection")
local utils = require("csv-table.actions.utils")

local M = {}

--- A column that moved is somewhere else on the line, so it flashes to be found
--- again. A column that only changed width has not gone anywhere.
---@param buf csv.Buffer
---@return fun(cell: integer)
local function flash(buf)
  return function(cell)
    cursor.flash_cell(buf, cell)
  end
end

---@param align "left"|"center"|"right"
---@return fun(buf: csv.Buffer)
local function aligner(align)
  return function(buf)
    utils.on_padding(buf, function(column, width)
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
    utils.on_padding(buf, function(column, current)
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
      utils.follow(buf, column, flash(buf))
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
      utils.follow(buf, held, flash(buf))
    end
  end
end

---@type table<string, csv.Action>
M.utils.actions = {
  next_column = utils.action("Move to the next column", function(buf)
    cursor.jump_column(buf, 0, 1)
  end),

  prev_column = utils.action("Move to the previous column", function(buf)
    cursor.jump_column(buf, 0, -1)
  end),

  hide_column = utils.action("Hide this column", function(buf)
    utils.on_column(buf, function(column)
      selection.hide_column(buf.state, column)
    end)
  end),

  show_all_columns = utils.action("Show every column again", function(buf)
    selection.show_all_columns(buf.state)
    buffer.render(buf)
  end),

  cut_column = utils.action("Cut this column, holding it to paste", function(buf)
    utils.on_column(buf, function(column)
      selection.cut_column(buf.state, column, false)
    end)
  end),

  cut_append_column = utils.action("Add this column to the cut being held", function(buf)
    utils.on_column(buf, function(column)
      selection.cut_column(buf.state, column, true)
    end)
  end),

  paste_columns_after = utils.action("Paste the held columns after this one", paster(false)),
  paste_columns_before = utils.action("Paste the held columns before this one", paster(true)),
  move_column_left = utils.action("Move this column one place left", mover(-1)),
  move_column_right = utils.action("Move this column one place right", mover(1)),

  align_left = utils.action("Align this column left", aligner("left")),
  align_center = utils.action("Align this column centre", aligner("center")),
  align_right = utils.action("Align this column right", aligner("right")),

  increase_precision = utils.action("Show one more decimal in this column", precision(1)),
  decrease_precision = utils.action("Show one fewer decimal in this column", precision(-1)),
  increase_width = utils.action("Widen this column by one", width(1)),
  decrease_width = utils.action("Narrow this column by one", width(-1)),

  set_format = utils.action("Give this column a printf format", function(buf)
    local column = cursor.column_at(buf, 0)
    if not column then
      return query.report("the cursor is not on a column")
    end

    local current = buf.state.formats[column.index]
    vim.ui.input({ prompt = "printf format: ", default = current and current.spec or "" }, function(spec)
      if spec == nil then
        return
      end
      format.set_spec(buf.state.formats, column, spec)
      buffer.render(buf)
    end)
  end),
}

return M
