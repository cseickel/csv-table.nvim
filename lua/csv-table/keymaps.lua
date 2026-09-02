--[[
Which key runs which action.

Kept apart from both the actions and the setup so the help panel can read it
without either depending on the other. A table passed to `setup` is merged over
`map`, and a key set to `false` there binds nothing.
]]

local M = {}

---@type table<string, string|false>
M.map = {
  ["l"] = "next_column",
  ["h"] = "prev_column",
  ["j"] = "next_row",
  ["k"] = "prev_row",
  ["<Right>"] = "next_column",
  ["<Left>"] = "prev_column",
  ["<Down>"] = "next_row",
  ["<Up>"] = "prev_row",
  ["<Tab>"] = "next_column",
  ["<S-Tab>"] = "prev_column",
  ["0"] = "first_column",
  ["$"] = "last_column",
  ["<Home>"] = "first_column",
  ["<End>"] = "last_column",
  ["gg"] = "first_row",
  ["G"] = "last_row",

  ["sa"] = "sort_asc",
  ["sd"] = "sort_desc",
  ["saa"] = "add_sort_key_asc",
  ["sdd"] = "add_sort_key_desc",
  ["ss"] = "remove_sort_key",
  ["cs"] = "clear_sort",

  ["|"] = "hide_column",
  ["c|"] = "show_all_columns",
  ["x"] = "cut_column",
  ["X"] = "cut_append_column",
  ["p"] = "paste_columns_after",
  ["P"] = "paste_columns_before",
  ["<"] = "move_column_left",
  [">"] = "move_column_right",

  ["m"] = "toggle_mark_row",
  ["<M-m>"] = "toggle_mark_column",
  ["fr"] = "filter_to_marked_rows",
  ["fc"] = "filter_to_marked_columns",
  ["fm"] = "filter_to_marked_both",
  ["cm"] = "clear_marks",

  ["f"] = "filter",
  ["<BS>"] = "pop_filter",
  ["cf"] = "clear_filters",

  ["al"] = "align_left",
  ["ac"] = "align_center",
  ["ar"] = "align_right",
  ["."] = "increase_precision",
  [","] = "decrease_precision",
  ["+"] = "increase_width",
  ["_"] = "decrease_width",
  ["@"] = "set_format",

  ["]"] = "next_page",
  ["["] = "prev_page",
  ["]]"] = "last_page",
  ["[["] = "first_page",
  ["[]"] = "set_page_size",

  ["v"] = "select_cell",
  ["V"] = "select_row",
  ["<S-Space>"] = "select_row",
  ["<C-Space>"] = "select_column",
  ["<C-a>"] = "select_page",
  ["<Esc>"] = "clear_selection",

  ["<S-Left>"] = "extend_left",
  ["<S-Right>"] = "extend_right",
  ["<S-Up>"] = "extend_up",
  ["<S-Down>"] = "extend_down",
  ["<C-S-Left>"] = "extend_to_first_column",
  ["<C-S-Right>"] = "extend_to_last_column",
  ["<C-S-Up>"] = "extend_to_first_row",
  ["<C-S-Down>"] = "extend_to_last_row",

  ["y"] = "copy",

  ["r"] = "refresh",
  ["cc"] = "clear_all",

  ["<enter>"] = "show_cell",
  ["gr"] = "show_row",
  ["gc"] = "show_column",
  ["gi"] = "show_file_info",
  ["gs"] = "select_sheet",
  ["?"] = "show_help",

}

return M
