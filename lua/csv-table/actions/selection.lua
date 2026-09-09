--[[
Registers the actions that pick cells out and export them.

Starting and resuming a selection are not here. Nvim's own visual modes say the
user is extending, and `csv-table.view.movement` takes the head along with every
move made in one, so `v`, `V` and `gv` all work with no action of ours.
]]

local picker = require("csv-table.popup.picker")
local utils = require("csv-table.actions.utils")

local EDGE = utils.EDGE

---@param rows integer
---@param cells integer
---@return fun(view: csv.View)
local function extender(rows, cells)
  return function(view)
    view:extend(rows, cells)
  end
end

--- Pick out the block `kind` covers, anchored on the active cell.
---@param kind csv.SelectionKind
---@return fun(view: csv.View)
local function selector(kind)
  return function(view)
    view:select_kind(kind)
  end
end

utils.register_action("select_column", "Select this whole column", selector("column"))
utils.register_action("select_page", "Select every cell on this page", selector("page"))

utils.register_action("clear_selection", "Select nothing", function(view)
  view:deselect()
end)

utils.register_action("swap_selection_ends", "Move to the other end of the selection", function(view)
  view:swap_ends()
end)

utils.register_action("extend_left", "Take the selection one column left", extender(0, -1))
utils.register_action("extend_right", "Take the selection one column right", extender(0, 1))
utils.register_action("extend_up", "Take the selection one row up", extender(-1, 0))
utils.register_action("extend_down", "Take the selection one row down", extender(1, 0))

utils.register_action(
  "extend_to_first_column",
  "Take the selection to the first column",
  extender(0, -EDGE)
)
utils.register_action(
  "extend_to_last_column",
  "Take the selection to the last column",
  extender(0, EDGE)
)
utils.register_action(
  "extend_to_first_row",
  "Take the selection to the top of the page",
  extender(-EDGE, 0)
)
utils.register_action(
  "extend_to_last_row",
  "Take the selection to the bottom of the page",
  extender(EDGE, 0)
)

utils.register_action("extend_to_click", "Take the selection out to the click", function(view)
  local position = vim.fn.getmousepos()
  if position.winid ~= view.window or position.column == 0 then
    return
  end

  local cell = view.buffer.page:cell_at(position.line, position.column - 1)
  if cell then
    view:extend_to(cell)
  end
end)

--- Every way the selected cells reach the clipboard. `display` is the text the
--- buffer already holds, and the rest are written by xan from the file.
---
--- `label` is what the picker offers, where the prompt has already said the word
--- yank. `description` is what the help panel shows beside the key, where the line
--- stands on its own.
---@type { action: string, format: string, headers: boolean, label: string, description: string }[]
local YANKS = {
  {
    action = "yank_tsv",
    format = "tsv",
    headers = true,
    label = "TSV",
    description = "Yank as tab separated values",
  },
  {
    action = "yank_tsv_no_headers",
    format = "tsv",
    headers = false,
    label = "TSV, no headers",
    description = "Yank as tab separated values, without the header row",
  },
  {
    action = "yank_csv",
    format = "csv",
    headers = true,
    label = "CSV",
    description = "Yank as CSV",
  },
  {
    action = "yank_csv_no_headers",
    format = "csv",
    headers = false,
    label = "CSV, no headers",
    description = "Yank as CSV, without the header row",
  },
  {
    action = "yank_display",
    format = "display",
    headers = true,
    label = "As displayed",
    description = "Yank the cells as they are drawn",
  },
  {
    action = "yank_display_no_headers",
    format = "display",
    headers = false,
    label = "As displayed, no headers",
    description = "Yank the cells as they are drawn, without the header row",
  },
  {
    action = "yank_json",
    format = "json",
    headers = true,
    label = "JSON",
    description = "Yank as JSON",
  },
  {
    action = "yank_markdown",
    format = "markdown",
    headers = true,
    label = "Markdown",
    description = "Yank as a markdown table",
  },
}

for _, yank in ipairs(YANKS) do
  utils.register_action(yank.action, yank.description, function(view)
    view:yank({ format = yank.format, headers = yank.headers })
  end)
end

utils.register_action("yank_picker", "Choose a format and yank the selected cells", function(view)
  picker.choose(YANKS, {
    prompt = "yank as",
    format_item = function(yank)
      return yank.label
    end,
  }, function(yank)
    view:yank({ format = yank.format, headers = yank.headers })
  end)
end)
