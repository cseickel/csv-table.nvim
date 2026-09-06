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

These are the defaults. Anything you pass to `setup()` merges into them and overrides what it names.

```lua
require("csv-table").setup({
  -- Which files open as a table. Only formats supported by xan are valid.
  -- Parquet has partial support, but I would not recommend it because it is
  -- not as optimized and not all column types are supported.
  patterns = { "*.csv", "*.tsv", "*.xls", "*.xlsx", "*.xlsb", "*.ods" },

  -- How many rows a page holds. `[]` changes it for one buffer.
  page_size = 1000,

  -- Key to action name.
  keymaps = {
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
    ["Y"] = "copy_without_headers",

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

Setting a key to `false` will prevent the default bind without setting a new one.

```lua
keymaps = {
  ["<C-n>"] = "next_column",
  ["<Tab>"] = false,
}
```

## Command

`:CsvTable [path]` opens `path`, or re-opens the current buffer's file. `:edit` on a matching extension will do the same thing after the plugin has loaded.

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
| `CsvCursorCell`     | `reverse`      | The active cell                                  |
| `CsvFlash`          | `IncSearch`    | The brief flash on a moved column                |
| `CsvHiddenCursor`   | `blend = 100`  | The real cursor, while a table buffer is current |

`CsvRowNumber` used to be named `CsvRowId`. A config that links `CsvRowId` has to be changed to the new name.

Columns are color coded by data type. The type comes from a 600-row sample: numeric when every value parses as a number, date when every value matches a date or time, and text otherwise. In a numeric column, `CsvNumberNegative` applies to the values starting with a minus sign and `CsvNumberPositive` to the rest.

## Keys

All mappings are buffer-local in a csv-table buffer. Hit `?` to open a list of all actions and run one.

### Moving

| Key       | Action         | Does                                        |
|-----------|----------------|---------------------------------------------|
| `l`       | `next_column`  | Move to the next column                     |
| `h`       | `prev_column`  | Move to the previous column                 |
| `j`       | `next_row`     | Move down a row                             |
| `k`       | `prev_row`     | Move up a row                               |
| `<Right>` | `next_column`  | Move to the next column                     |
| `<Left>`  | `prev_column`  | Move to the previous column                 |
| `<Down>`  | `next_row`     | Move down a row                             |
| `<Up>`    | `prev_row`     | Move up a row                               |
| `<Tab>`   | `next_column`  | Move to the next column                     |
| `<S-Tab>` | `prev_column`  | Move to the previous column                 |
| `0`       | `first_column` | Move to the first column                    |
| `$`       | `last_column`  | Move to the last column                     |
| `<Home>`  | `first_column` | Move to the first column                    |
| `<End>`   | `last_column`  | Move to the last column                     |
| `gg`      | `first_row`    | Move to the top of the page, or to row N    |
| `G`       | `last_row`     | Move to the bottom of the page, or to row N |

Column one is the row number: the row's position in the table as filtered and sorted, counted from 1. It is a position in the view rather than a line of the file, so after a sort the first row on screen is row 1 whichever line of the file it came from. Numbering runs on across pages, so with a page size of 1000 the second page starts at 1001.

The table has an active cell, the way a spreadsheet does. It is drawn with `CsvCursorCell` and the real cursor is hidden while a table buffer is current. The cursor is constrained to always be in a data cell and never on a border, the row number, the header, or past the table. All movements are by whole cells, and a count moves that many cells, except that `5gg` and `5G` go to the row numbered 5, which is the number drawn in column one. A number belonging to another page stops at the near end of this one. Any other motion that lands outside a cell, whether a mouse click, `/`, `w` or `%`, is snapped into the nearest one.

Hiding the cursor needs `termguicolors` and a terminal that supports cursor styling. Without them the cursor shows as a block at one edge of the active cell.

### Filtering

| Key    | Action          | Does                       |
| ------ | --------------- | -------------------------- |
| `f`    | `filter`        | Filter on this column      |
| `<BS>` | `pop_filter`    | Drop the filter added last |
| `cf`   | `clear_filters` | Drop every filter          |

`f` opens a dialog with comparisons that make sense for the column. Numeric columns get `>`, `>=`, `<`, `<=`, `==` and `!=`. Text columns get equals, not equals, contains, starts with, ends with and regex. Every column gets `v` and `e` as well.

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

| Key   | Action                 | Does                                   |
|-------|------------------------|----------------------------------------|
| `\|`  | `hide_column`          | Hide this column                       |
| `c\|` | `show_all_columns`     | Show every column again                |
| `x`   | `cut_column`           | Cut this column, holding it to paste   |
| `X`   | `cut_append_column`    | Add this column to the cut being held  |
| `p`   | `paste_columns_after`  | Paste the held columns after this one  |
| `P`   | `paste_columns_before` | Paste the held columns before this one |
| `<`   | `move_column_left`     | Move this column one place left        |
| `>`   | `move_column_right`    | Move this column one place right       |
| `+`   | `increase_width`       | Widen this column by one               |
| `_`   | `decrease_width`       | Narrow this column by one              |

### Formatting

| Key  | Action               | Does                                  |
| ---- | -------------------- | ------------------------------------- |
| `al` | `align_left`         | Align this column left                |
| `ac` | `align_center`       | Align this column centre              |
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

`<enter>` reads the value from the file, so it shows the full text even when the column draws it cut, and before any formatting. A value that is a JSON object or array is indented one value per line and highlighted as JSON, with the numbers, key order and escapes exactly as stored. `gr` opens a picker over every column of the row, in file order so hidden columns are included, searchable by column name or by value. Choosing one copies its value to the `+` register. `?` opens a picker over every binding, searchable, and runs the one chosen.

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

| Key           | Action                   | Does                                             |
| ------------- | ------------------------ | ------------------------------------------------ |
| `v`           | `select_cell`            | Select this cell                                 |
| `V`           | `select_row`             | Select this whole row                            |
| `<S-Space>`   | `select_row`             | Select this whole row                            |
| `<C-Space>`   | `select_column`          | Select this whole column                         |
| `<C-a>`       | `select_page`            | Select every cell on this page                   |
| `<Esc>`       | `clear_selection`        | Select nothing                                   |
| `<S-Left>`    | `extend_left`            | Take the selection one column left               |
| `<S-Right>`   | `extend_right`           | Take the selection one column right              |
| `<S-Up>`      | `extend_up`              | Take the selection one row up                    |
| `<S-Down>`    | `extend_down`            | Take the selection one row down                  |
| `<C-S-Left>`  | `extend_to_first_column` | Take the selection to the first column           |
| `<C-S-Right>` | `extend_to_last_column`  | Take the selection to the last column            |
| `<C-S-Up>`    | `extend_to_first_row`    | Take the selection to the top of the page        |
| `<C-S-Down>`  | `extend_to_last_row`     | Take the selection to the bottom of the page     |
| `y`           | `copy`                   | Copy the selected cells under their column names |
| `Y`           | `copy_without_headers`   | Copy the selected cells alone                    |

Extending moves the cursor with the selection, the way a spreadsheet moves the active cell, so the shifted arrows also walk the table. Moving the cursor without shift drops the selection, as in a spreadsheet. A selection stops at the page, and turning the page loses it.

`y` copies the selected cells to the `+` register as tab separated text, which pastes into a spreadsheet as cells, under a header row of the column names as the file spells them. `Y` copies the same cells without that header row. With nothing selected, either key copies the cell under the cursor. The values come from the file, so a column too narrow to show its values still copies them whole, and a value holding a tab or a newline comes out quoted.

The Excel keys, `<S-Space>`, `<C-Space>` and the `<C-S-Arrow>` set, need a terminal that implements the kitty keyboard protocol, which ghostty, kitty and wezterm do.

## License

MIT. See `LICENSE`.
