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

Nvim's own visual modes are how you tell the plugin you are selecting, so a remapped `<C-v>` works too. `v` runs `<C-v>` in a table buffer, since charwise visual covers whole lines between its two ends, so it starts a blockwise selection and pressing it again ends visual mode, the same as `<C-v>` does. `V` selects whole rows. While you are in visual mode, every move takes the far end of the selection with it.

Nvim's visual region and the plugin's selection cover the same cells. Entering visual mode with cells already selected keeps the anchor and takes the other end to the cell you are on, so `<S-Right>` a few times, `<S-Down>`, a plain move or two and then `v` gives you a block from the original anchor to where you are standing. Nvim's region has no way to hold every row of a column, so a column or page selection and a visual mode cannot both be running. `v` over a `<C-Space>` or `<C-a>` selection turns it into a cell block from the anchor to the cell you are on, and `V` turns it into whole rows. `<C-Space>` or `<C-a>` pressed inside visual mode ends the mode and then selects the column or the page. Since nvim's region covers the same block, a visual mode mapping of your own, or one from another plugin, acts on the cells the table has picked out.

Every key in this README works inside visual mode. A key that moves the active cell and takes the selection with it leaves you in visual mode: `l`, `h`, `<Left>`, `<Right>`, `<Tab>`, `<S-Tab>`, `gg`, `G`, `o`, `<S-LeftMouse>`, the shifted arrows and the `<C-S-Arrow>` set. Every other key ends visual mode before it runs, the way nvim's own `y` does, and the cells stay selected, so `y` over a selection yanks it and leaves you in normal mode with the cells still drawn.

The selection survives leaving visual mode, so `y` from normal mode still yanks those cells. `<Esc>` clears the selection, and in visual mode it ends the mode in the same press. The block it cleared stays in the `'<` and `'>` marks.

`gv` is nvim's own and it brings the block back, cleared or not. Every change to the selection is written to `'<` and `'>`, and entering visual mode with nothing selected reads those two marks back as cells, so what nvim reselects is what the plugin then draws. Inside a table buffer those two marks hold the cell block rather than the last text you selected.

`o` is the plugin's rather than nvim's, because a selection outlives the visual mode it was made in, and once the mode has ended nvim's `o` has no region left to swap.

A move without shift moves the active cell and leaves the selection where it was, so you can walk away, look at something, and come back. The next shifted move extends from the same anchor to wherever you are now. The shifted arrows and the `<C-S-Arrow>` set extend the selection and walk the active cell along, in visual mode or out of it, and with nothing selected they start from the active cell. `<S-LeftMouse>` takes the selection out to the cell you clicked and moves the active cell there. A selection stops at the edges of the page. It clears when the rows on the page change or the columns are reordered, so a sort, a filter, a page turn and a hidden column all lose it. Changing how a column is drawn keeps it, and so does marking a row, unless a filter is showing the marked rows only.

The Excel keys, `<C-Space>` and the `<C-S-Arrow>` set, need a terminal that implements the kitty keyboard protocol, which ghostty, kitty and wezterm do.

#### Selecting with the mouse

Press on a cell and drag to select the block from that cell to the cell under the pointer. The table window has to have focus already: a press that moves focus into it from a window showing anything else only focuses it, and the drag after that press does nothing. A drag that starts on a statusline or a window separator resizes windows the way it always does.

Hold the pointer near an edge of the window, or past it, and the selection keeps stepping that way on its own, scrolling the window as it goes. Near the top or bottom edge means inside the rows your `scrolloff` keeps above and below the cursor. Near the left or right edge means inside the 8 columns the table keeps in view beside the active cell, where it draws a slice of the next column. The farther out the pointer is, the faster the steps come:

| Direction      | Pointer                                   | One step every                  |
|----------------|-------------------------------------------|---------------------------------|
| Up and down    | the `scrolloff` rows, from inner to outer | 150 ms, falling evenly to 25 ms |
| Up and down    | past the window                           | 25 ms                           |
| Left and right | the inner 4 of the 8 columns              | 300 ms                          |
| Left and right | the outer 4, or past the window           | 100 ms                          |

With `scrolloff` at 0 or 1 there are too few rows to fall evenly across, so the first row past the edge steps every 150 ms and every row beyond it every 25 ms. On the last column the table keeps no columns beside the active cell, and there is nothing further right to step to.

`<S-LeftMouse>` needs a terminal that passes shift+click through to nvim, and many keep it for their own text selection. In ghostty, set `mouse-shift-capture = true`.

#### Yanking

Every yank writes the selected cells to the `+` register and the unnamed register, so `p` pastes them inside nvim and the clipboard has them outside it. `y` yanks them as tab separated values under a header row, which pastes into a spreadsheet as cells. `Y` opens a picker over every format. With nothing selected, every yank takes the active cell.

A single cell, selected or active, is yanked as its bare value, trimmed and without a header, in every format. `display` gives the text drawn in the cell, and every other format gives the value the file holds.

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

Only `yank_tsv` and `yank_picker` have keys. Any of the others can be bound in `keymaps`.

`display` is the text on screen. It cuts the selected columns out of the lines the table drew, header line first, so a value drawn cut is yanked cut and the yank matches what you see. Every other format reads the values from the file, so a column too narrow to show its values still yanks them whole, and a value holding a tab or a newline comes out quoted.

`tsv` and `csv` keep the header text as the file spells it. `json` and `markdown` name each column by its label, which is the header text with `[n]` appended where a name repeats, because a JSON object and a markdown header both need one name per column.

## License

MIT. See `LICENSE`.
