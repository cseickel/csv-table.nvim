--[[
Holds `map`, every key the plugin binds and the action it runs.

- `M.stays_visual` names the actions that leave nvim in its visual mode
- `resolve` turns `map` into the bindings `init.apply_keymaps` sets
- `built_in` reads the `BUILT_IN_` prefix

A key written `BUILT_IN_l` names the nvim command `l` rather than the key `l`,
and `resolve` puts the action wherever that command lives in the user's config.
A user whose `l` moves between windows decided what `l` means, and `next_column`
stays off it. A value written the same way runs an nvim command in place of an
action, which is how `v` starts a blockwise selection.

A movement key is bound only where a count has to mean something in table terms:
`5l` is five cells and `5G` is the row the gutter numbers 5. Every other motion,
`j` and `w` and `/` and the clicks, stays nvim's, and the cursor is followed to
whichever cell it reached.

Every key is bound in normal mode and in nvim's visual modes, since nvim's own
visual commands are no use over a table: `y` there takes the painted text cut to
the width each column is drawn at, and the rest are edits this buffer refuses. An
action run from a visual mode ends that mode first, the way nvim's own `y` does,
and `M.stays_visual` names the ones that do not.
]]

local M = {}

--- What marks a key or a value in `map` as the name of an nvim command.
local BUILT_IN = "BUILT_IN_"

---@type table<string, string|false>
M.map = {
  ["BUILT_IN_l"] = "next_column",
  ["BUILT_IN_h"] = "prev_column",
  ["BUILT_IN_<Right>"] = "next_column",
  ["BUILT_IN_<Left>"] = "prev_column",
  ["BUILT_IN_gg"] = "first_row",
  ["BUILT_IN_G"] = "last_row",
  ["<Tab>"] = "next_column",
  ["<S-Tab>"] = "prev_column",

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

  ["BUILT_IN_v"] = "BUILT_IN_<C-v>",
  ["<C-Space>"] = "select_column",
  ["<C-a>"] = "select_page",
  ["<Esc>"] = "clear_selection",
  ["<S-LeftMouse>"] = "extend_to_click",
  ["o"] = "swap_selection_ends",

  ["<S-Left>"] = "extend_left",
  ["<S-Right>"] = "extend_right",
  ["<S-Up>"] = "extend_up",
  ["<S-Down>"] = "extend_down",
  ["<C-S-Left>"] = "extend_to_first_column",
  ["<C-S-Right>"] = "extend_to_last_column",
  ["<C-S-Up>"] = "extend_to_first_row",
  ["<C-S-Down>"] = "extend_to_last_row",

  ["y"] = "yank_tsv",
  ["Y"] = "yank_picker",

  ["r"] = "refresh",
  ["cc"] = "clear_all",

  ["<enter>"] = "show_cell",
  ["gr"] = "show_row",
  ["gc"] = "show_column",
  ["gi"] = "show_file_info",
  ["gs"] = "select_sheet",
  ["?"] = "show_help",

}

--- The actions that take the head of the selection with them or pick the block
--- out, which is why nvim is left in its visual mode when one of them runs.
---@type string[]
M.stays_visual = {
  "next_column",
  "prev_column",
  "next_row",
  "prev_row",
  "first_column",
  "last_column",
  "first_row",
  "last_row",

  "swap_selection_ends",
  "extend_to_click",
  "extend_left",
  "extend_right",
  "extend_up",
  "extend_down",
  "extend_to_first_column",
  "extend_to_last_column",
  "extend_to_first_row",
  "extend_to_last_row",
}

---@param key string
---@return string
local function keycodes(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

--- Whether binding `key` inside a table buffer would spoil one of `bound`. A
--- key that starts another one, `s` against `sa`, leaves both waiting on
--- `timeoutlen` and one of them out of reach.
---@param key string In keycodes, as the members of `bound` are.
---@param bound string[]
---@return boolean
local function collides(key, bound)
  for _, taken in ipairs(bound) do
    if key:sub(1, #taken) == taken or taken:sub(1, #key) == key then
      return true
    end
  end
  return false
end

--- The nvim command `value` names, present when `value` is written
--- `BUILT_IN_l` rather than naming a key or an action.
---@param value string
---@return string|nil
function M.built_in(value)
  return value:match("^" .. BUILT_IN .. "(.+)$")
end

--- Every key to bind and what it runs, an action name or an nvim command, with
--- each `BUILT_IN_` key turned into the keys that run that command in this
--- user's config.
---
--- Only a `noremap` mapping is followed, because `nmap <M-l> l` runs whatever
--- the user has made `l` mean rather than nvim's own `l`. A `<Plug>` name is
--- left alone, since the plugin that defined it is the only thing meant to run
--- it. A mapping written as a Lua function has no key sequence to read, so a
--- user who wrapped `l` in one is taken to have kept `l` for themselves.
---@class csv.Binding
---@field key string
---@field action string|nil Names an action in `csv-table.actions`.
---@field command string|nil An nvim command to run in its place.
---@field stays_visual boolean Whether the action leaves nvim in its visual mode.

---@return csv.Binding[]
function M.resolve()
  local stays = {}
  for _, action in ipairs(M.stays_visual) do
    stays[action] = true
  end

  local bindings = {}
  local literal = {}
  local commands = {}

  ---@param key string
  ---@param entry csv.Binding
  local function bind(key, entry)
    table.insert(bindings, {
      key = key,
      action = entry.action,
      command = entry.command,
      stays_visual = entry.stays_visual,
    })
  end

  for key, runs in pairs(M.map) do
    if runs then
      local command = M.built_in(runs)
      local entry = {
        key = key,
        action = command == nil and runs or nil,
        command = command,
        stays_visual = stays[runs] == true,
      }

      local named = M.built_in(key)
      if named then
        commands[keycodes(named)] = { key = named, entry = entry }
      else
        table.insert(literal, keycodes(key))
        bind(key, entry)
      end
    end
  end

  local claimed = {}
  for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
    local lhs = keycodes(mapping.lhs)
    claimed[lhs] = true

    local wanted = mapping.rhs and mapping.noremap == 1 and commands[keycodes(mapping.rhs)]
    if wanted and not mapping.lhs:find("^<Plug>") and not collides(lhs, literal) then
      bind(mapping.lhs, wanted.entry)
    end
  end

  for named, wanted in pairs(commands) do
    if not claimed[named] then
      bind(wanted.key, wanted.entry)
    end
  end

  return bindings
end

return M
