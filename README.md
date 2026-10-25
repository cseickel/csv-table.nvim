# csv-table.nvim

A spreadsheet viewer for Neovim.

`csv`, `tsv`, `xls`, `xlsx`, `xlsb` and `ods` files open as a bordered, paged table with sorting, filtering, and per-column formatting. All operations, including drawing the table, are done with [`xan`](https://github.com/medialab/xan) so you can effectively view and manipulate huge files.

Buffers are read-only, but controlled, spreadsheet style editing is planned.

## Requirements

Neovim 0.10 or newer, and [`xan`](https://github.com/medialab/xan) on your `PATH`.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cseickel/csv-table.nvim",
  lazy = false,
  opts = {},
}
```

`setup()` has to run before you open a CSV because the plugin works by intercepting csv files and replacing them with the table view.

## Options

All options shown below are the defaults. Anything you set will be merged into these. Anything not specified will use the default values shown below.

```lua
require("csv-table").setup({
  -- The file extensions that automatically open as a table. Case is ignored,
  -- Any format xan reads can go here. You can still manually open a file with
  -- `:CsvTable` without having to list it here. Parquet has partial support,
  -- but I would not recommend it because it is not as optimized and not all
  -- column types are supported.
  extensions = { "csv", "tsv", "xls", "xlsx", "xlsb", "ods" },

  -- How many rows a page holds. `[]` changes it for one buffer.
  page_size = 1000,

  -- Key to action name. A key written `BUILT_IN_l` names the nvim command
  -- `l` rather than the key `l`, and the action goes wherever your config
  -- runs that command. See Moving below.
  keymaps = {
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
  },
})
```

Setting a key to `false` prevents the default bind without setting a new one.

The special keys `BUILT_IN_` refer to the native vim command for that key, so if you have mapped something else to that action, then that is what actually triggers the action. This is needed because we need to override some basic things like movement and visual selection to work in cells and not characters. So if you have mapped "move left" to `a` instead of `l`, then `a` moves you one cell left, and `5a` moves 5 cells to the left.

The other special situation is visual mode. `v` for visual selection does not actually work correctly in a table, but it is naturally to use as a block selection so we remap is to `<C-v>` instead which does work well. The `["BUILT_IN_v"] = "BUILT_IN_<C-v>"` syntax allows us to specify that behavior as configuration.

## Command

`:CsvTable [path]` opens `path` as a table. This is only needed if the file's extension is not listed in the extensions config, which would make it open as a table automatically. That buffer stays a table through every later `:edit` until it is wiped. **Any file opened as a table is not editable.**

`:CsvTable --disable` gives the buffer back and reads the file as text. If the file was listed in the extensions for automatic handling, then it becomes a table again every time you `:edit` it. If not, it stays as text until you run `:CsvTable` again.

When a file is read as a table, it goes to `xan`, which tells formats apart by extension. Beside the csv, tsv and workbook formats in the default `extensions`, it can also read json, jsonl and ndjson, toml, txt, npy, tar and md. A json object nested in a record flattens to dotted column names, so `{"c": {"d": 2}}` becomes a column `c.d`, and an array arrives as its json text, `[1,2]`. `xan` picks the columns of a json or jsonl file from its first 64 records, so a key that first appears after them is dropped.

## Statusline

```lua
require("csv-table").status(bufnr)
```

This is to show csv-table information in your statusline or winbar. It does not automatically work with any statusline plugin, but it should not be difficult to figure it out if you use one.

`require("csv-table").status(bufnr)` returns a one-line summary for a csv-table buffer: sheet, rows on screen, active filters and marks, the sort, and any cut columns in the register. Other buffers return an empty string.

```lua
_G.csv_table_status = function()
  local ok, csv_table = pcall(require, "csv-table")
  if not ok then
    return ""
  end
  local text = csv_table.status(vim.api.nvim_get_current_buf())
  return text == "" and "" or (" " .. text .. " ")
end

vim.o.statusline = "%{%v:lua.csv_table_status()%}"
```

## Winbar

`b:table_header` holds the buffer line the header row is drawn on. A winbar can read it to keep the header on screen once the table has scrolled past it. The plugin does not set any winbar for you. 

Here is what I use to keep the headers locked to the top on scroll:

```lua
-- ~/.config/nvim/lua/status.lua
local M = {}

M.get_header = function()
	local header_line = vim.b.table_header or 1
	-- Sets the winbar to the header line of the buffer, but only if the buffer is
	-- scrolled down so that the header is not visible.
	local view = vim.fn.winsaveview()
	if view.topline <= header_line then
		return nil
	else
		-- get the gutter width
		local winid = vim.api.nvim_get_current_win()
		local wininfo = vim.fn.getwininfo(winid)
		if #wininfo == 0 then
			return nil
		end
		local textoff = wininfo[1].textoff
		local gutter = string.rep(" ", textoff)

    local text = vim.fn.getline(header_line)
    -- Cut to the portion of the header that's visible
    local width = vim.api.nvim_win_get_width(winid) - textoff
    text = vim.fn.strcharpart(text, view.leftcol, width)
    -- Escape any % in the header text
    text = text:gsub("%%", "%%%%")
    -- replace all │ with bars wrapped in CsvBorder highlight group
    text = text:gsub("│", "%%#CsvBorder#│%%#WinBarHeader#")
		-- add textoff to the beginning of the text
		-- ensure the text is left aligned
		return gutter .. "%#WinBarHeader#" .. text .. "%*%<"
	end
end

M.get_winbar = function()
	-- floating window
	local cfg = vim.api.nvim_win_get_config(0)
	if cfg.relative > "" or cfg.external then
		return ""
	end

	if vim.b.table_header then
		local header = M.get_header()
		if header then
			return header
		end
	end
end

vim.cmd([[
  highlight WinBar           guibg=None guifg=#BBBBBB gui=bold
  highlight WinBarHeader     guibg=None guifg=#BBBBBB gui=bold,underline
]])

_G.status = M
vim.o.winbar = "%{%v:lua.status.get_winbar()%}"

return M
```

## Highlights

The following highlight groups are defined by the plugin:

| Group               | Default        | Used for                                         |
|---------------------|----------------|--------------------------------------------------|
| `CsvHeader`         | bold `#ededed` | The header row                                   |
| `CsvBorder`         | `#444444`      | The lines the table is drawn with                |
| `CsvRowNumber`      | `CsvBorder`    | The row number in column one                     |
| `CsvNumberPositive` | `#85e0b1`      | A positive number                                |
| `CsvNumberNegative` | `#ff8066`      | A negative number                                |
| `CsvDate`           | `#ffd685`      | A date or a time                                 |
| `CsvMarkedRow`      | `DiffAdd`      | A row you marked with `m`                        |
| `CsvMarkedColumn`   | `DiffText`     | A column you marked with `<M-m>`                 |
| `CsvSelection`      | `Visual`       | The cells you selected with `v`                  |
| `CsvActiveCell`     | `reverse`      | The active cell                                  |
| `CsvFlash`          | `IncSearch`    | The brief flash on a moved column                |
| `CsvHiddenCursor`   | `blend = 100`  | The real cursor, while a table buffer is current |

`CsvRowNumber` used to be named `CsvRowId`. A config that links `CsvRowId` has to be changed to the new name.

Columns are color coded by data type. The type comes from a 600-row sample: numeric when every value parses as a number, date when every value matches a date or time, and text otherwise. In a numeric column, `CsvNumberNegative` applies to the values starting with a minus sign and `CsvNumberPositive` to the rest.

## Row Numbers

The status column shows the row number, meaning the row's position in the table as filtered and sorted, counted from 1. It is a position in the view rather than a line of the file, so after a sort the first row on screen is row 1 whichever line of the file it came from. Numbering runs on across pages, so with a page size of 1000 the second page starts at 1001.

## Keys

All mappings created by this plugin are buffer-local in a csv-table buffer. Hit `?` to open a list of all actions and run one.

### Moving

| Key       | Action        | Does                                        |
|-----------|---------------|---------------------------------------------|
| `l`       | `next_column` | Move to the next column                     |
| `h`       | `prev_column` | Move to the previous column                 |
| `<Right>` | `next_column` | Move to the next column                     |
| `<Left>`  | `prev_column` | Move to the previous column                 |
| `<Tab>`   | `next_column` | Move to the next column                     |
| `<S-Tab>` | `prev_column` | Move to the previous column                 |
| `gg`      | `first_row`   | Move to the top of the page, or to row N    |
| `G`       | `last_row`    | Move to the bottom of the page, or to row N |


The table has an active cell, the way a spreadsheet does. It is drawn with `CsvActiveCell` and the real cursor is hidden while a table buffer is current. Movements work with your normal bindings, but horizontal movements are converted from character movements to cell movements. So `5l` moves 5 cells to the right.

A click on a cell makes that cell active and clears the selection. Selecting with the mouse is covered under Selecting.

`next_row`, `prev_row`, `first_column` and `last_column` are actions you can bind. None is bound by default, because `j` and `0` already land on the right cell.

Hiding the cursor needs `termguicolors` and a terminal that supports cursor styling. Without them the cursor shows as a block at one edge of the active cell.

### Filtering

| Key    | Action          | Does                       |
| ------ | --------------- | -------------------------- |
| `f`    | `filter`        | Filter on this column      |
| `<BS>` | `pop_filter`    | Drop the filter added last |
| `cf`   | `clear_filters` | Drop every filter          |

`f` opens a filter dialog with comparisons that make sense for the column. Numeric columns get `>`, `>=`, `<`, `<=`, `==` and `!=`. Text columns get equals, not equals, contains, starts with, ends with and regex. Every column gets `v` and `e` as well.

- `v` shows the column's distinct values with counts, as a checklist. `<Space>` toggles, `<CR>` applies.
- `e` lets you write a [moonblade](https://github.com/medialab/xan) expression by hand.

Filters are ANDed.

### Sorting

| Key   | Action              | Does                                               |
| ----- | ------------------- | -------------------------------------------------- |
| `sa`  | `sort_asc`          | Sort by this column ascending, or clear that sort  |
| `sd`  | `sort_desc`         | Sort by this column descending, or clear that sort |
| `saa` | `add_sort_key_asc`  | Add this column to the sort, ascending             |
| `sdd` | `add_sort_key_desc` | Add this column to the sort, descending            |
| `ss`  | `remove_sort_key`   | Drop this column from the sort                     |
| `cs`  | `clear_sort`        | Clear the sort entirely                            |

Sorted columns get an arrow in the header. Sort on several and the arrows are numbered, most significant first.

### Columns

| Key   | Action                 | Does                                  |
|-------|------------------------|---------------------------------------|
| `\|`  | `hide_column`          | Hide this column                      |
| `c\|` | `show_all_columns`     | Show every column again               |
| `x`   | `cut_column`           | Cut this column, keeping it to paste  |
| `X`   | `cut_append_column`    | Add this column to the cut            |
| `p`   | `paste_columns_after`  | Paste the cut columns after this one  |
| `P`   | `paste_columns_before` | Paste the cut columns before this one |
| `<`   | `move_column_left`     | Move this column one place left       |
| `>`   | `move_column_right`    | Move this column one place right      |
| `+`   | `increase_width`       | Widen this column by one              |
| `_`   | `decrease_width`       | Narrow this column by one             |

A column you have not resized with `+` or `_` is drawn at most 100 characters wide, and a longer value is cut. `+` widens a column past that, and `<enter>` shows one value whole.

### Formatting

| Key  | Action               | Does                                  |
| ---- | -------------------- | ------------------------------------- |
| `al` | `align_left`         | Align this column left                |
| `ac` | `align_center`       | Align this column center              |
| `ar` | `align_right`        | Align this column right               |
| `.`  | `increase_precision` | Show one more decimal in this column  |
| `,`  | `decrease_precision` | Show one fewer decimal in this column |
| `@`  | `set_format`         | Give this column a printf format      |

Numeric columns get a sensible number of decimals automatically, so prices dumped from a float32 read as `199.59` rather than `199.589996338`. These keys override that. An empty `@` prompt puts the column back on the automatic decimals.

### Info Dialogs

| Key       | Action           | Does                                    |
| --------- | ---------------- | --------------------------------------- |
| `<enter>` | `show_cell`      | Show everything this cell holds         |
| `gr`      | `show_row`       | Show pivoted row values                 |
| `gc`      | `show_column`    | Summarize this column                   |
| `gi`      | `show_file_info` | Describe this file and the current view |
| `gs`      | `select_sheet`   | Choose which sheet to read              |
| `?`       | `show_help`      | Search every key and run one            |

`<enter>` reads the value from the file, so it shows the full text even when the column draws it cut, and before any formatting. A value that is a JSON object or array is indented one value per line and highlighted as JSON, with the numbers, key order and escapes exactly as stored. `gr` opens a picker over every column of the row, in file order so hidden columns are included, searchable by column name or by value. Choosing one copies its value to the `+` register. `?` opens a picker over every action, searchable, and runs the one chosen, so an action with no key is still one press away.

`gc` and `gi` respect your current filters. `gs` only applies to workbooks, and switching sheets clears your filters and formats. Panels close with `q` or `<Esc>`.

### Marking

| Key     | Action                     | Does                                       |
| ------- | -------------------------- | ------------------------------------------ |
| `m`     | `toggle_mark_row`          | Mark or unmark this row                    |
| `<M-m>` | `toggle_mark_column`       | Mark or unmark this column                 |
| `fr`    | `filter_to_marked_rows`    | Show only marked rows, or stop doing so    |
| `fc`    | `filter_to_marked_columns` | Show only marked columns, or stop doing so |
| `fm`    | `filter_to_marked_both`    | Show only marked rows and marked columns   |
| `cm`    | `clear_marks`              | Clear every marked row and column          |

Marks survive filtering and sorting.

### Paging

| Key  | Action          | Does                              |
| ---- | --------------- | --------------------------------- |
| `]`  | `next_page`     | Show the next page                |
| `[`  | `prev_page`     | Show the previous page            |
| `]]` | `last_page`     | Show the last page                |
| `[[` | `first_page`    | Show the first page               |
| `[]` | `set_page_size` | Choose how many rows a page holds |

`[]` sets the page size for one buffer. `page_size` sets it for all of them.

### Resetting

| Key  | Action      | Does                                          |
| ---- | ----------- | --------------------------------------------- |
| `r`  | `refresh`   | Read the file again                           |
| `cc` | `clear_all` | Clear filters, sort, marks and hidden columns |

### Selecting

Selecting is a mix of Excel and vim. You can use Excel's keys and the mouse, or nvim's visual modes. Both make the same selection, so you can start it one way and finish it the other.

| Key             | Action                   | Does                                             |
| --------------- | ------------------------ | ------------------------------------------------ |
| `<C-Space>`     | `select_column`          | Select this whole column                         |
| `<C-a>`         | `select_page`            | Select every cell on this page                   |
| `<Esc>`         | `clear_selection`        | Select nothing                                   |
| `<S-LeftMouse>` | `extend_to_click`        | Take the selection out to the click              |
| `<S-Left>`      | `extend_left`            | Take the selection one column left               |
| `<S-Right>`     | `extend_right`           | Take the selection one column right              |
| `<S-Up>`        | `extend_up`              | Take the selection one row up                    |
| `<S-Down>`      | `extend_down`            | Take the selection one row down                  |
| `<C-S-Left>`    | `extend_to_first_column` | Take the selection to the first column           |
| `<C-S-Right>`   | `extend_to_last_column`  | Take the selection to the last column            |
| `<C-S-Up>`      | `extend_to_first_row`    | Take the selection to the top of the page        |
| `<C-S-Down>`    | `extend_to_last_row`     | Take the selection to the bottom of the page     |
| `o`             | `swap_selection_ends`    | Move to the other end of the selection           |
| `y`             | `yank_tsv`               | Yank the selected cells as tab separated values  |
| `Y`             | `yank_picker`            | Choose a format and yank the selected cells      |

To select a range of cells, hold shift and use the arrow keys.

The selection stays until you press `<Esc>`, even after you yank it or move without shift. The next shifted move extends it from where it started to where you are now.

To select whole rows, press `V` and move up or down.

To select whole columns, press `<C-Space>`, then hold shift and move left or right to add more.

To select a block of cells with vim motions, press `<C-v>` and move.

`v` selects a block too, the same as `<C-v>`. A normal `v` selection would run from the end of one row into the start of the next. That's never what you want in a table.

#### Selecting with the mouse

Click and drag to select. If you're coming from another window, click the table once to focus it first.

Dragging near or past an edge scrolls the table. The farther out the pointer is, the faster it scrolls:

| Direction      | Pointer                                         | Moves one cell every                     |
|----------------|-------------------------------------------------|------------------------------------------|
| Up and down    | in the `scrolloff` rows next to the edge        | 150 ms, speeding up to 25 ms at the edge |
| Up and down    | past the edge                                   | 25 ms                                    |
| Left and right | 5 to 8 characters from the edge                 | 300 ms                                   |
| Left and right | 4 or fewer characters from the edge, or past it | 100 ms                                   |

#### Yanking

`y` copies the selection to the clipboard as tab separated values with a header row, so it pastes into Excel as cells. `Y` lets you pick the format.

| Action                    | Does                                                        |
| ------------------------- | ----------------------------------------------------------- |
| `yank_tsv`                | Yank as tab separated values                                |
| `yank_tsv_no_headers`     | Yank as tab separated values, without the header row        |
| `yank_csv`                | Yank as CSV                                                 |
| `yank_csv_no_headers`     | Yank as CSV, without the header row                         |
| `yank_display`            | Yank the cells as they are drawn                            |
| `yank_display_no_headers` | Yank the cells as they are drawn, without the header row    |
| `yank_json`               | Yank as JSON                                                |
| `yank_markdown`           | Yank as a markdown table                                    |

Every format except `display` copies the values from the file. They ignore your number formats and include any text the table cut off.

Bind any of these in `keymaps` to give a format its own key.

## License

MIT. See `LICENSE`.
