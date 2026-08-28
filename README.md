# csv-table.nvim

A spreadsheet viewer for Neovim.

`csv`, `tsv`, `xls`, `xlsx`, `xlsb` and `ods` files open as a bordered, paged table with sorting, filtering, and per-column formatting. All operations, including drawaing the table, are done with [`xan`](https://github.com/medialab/xan) so you can effectively view and manipulate huge files.

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

This shows the default options, which are all optional. Anything you do set will merge into and override these defaults.

```lua
require("csv-table").setup({
  -- Which files open as a table. Only formats supported by xan are valid.
  -- Parquet has partial support, but I would not recommend it because it is
  -- not as optimized and not all column types are supported.
  patterns = { "*.csv", "*.tsv", "*.xls", "*.xlsx", "*.xlsb", "*.ods" },

  -- How many rows a page holds. `<leader>ps` changes it for one buffer.
  page_size = 1000,

  -- Key to action name.
  keymaps = {
    ["<Tab>"] = "next_column",
    ["<S-Tab>"] = "prev_column",

    ["sa"] = "sort_asc",
    ["sd"] = "sort_desc",
    ["Sa"] = "add_sort_key_asc",
    ["Sd"] = "add_sort_key_desc",
    ["ss"] = "remove_sort_key",
    ["sc"] = "clear_sort",

    ["h"] = "hide_column",
    ["x"] = "cut_column",
    ["X"] = "cut_append_column",
    ["p"] = "paste_columns_after",
    ["P"] = "paste_columns_before",
    ["<"] = "move_column_left",
    [">"] = "move_column_right",
    ["<leader>X"] = "show_all_columns",

    ["m"] = "toggle_mark_row",
    ["<M-m>"] = "toggle_mark_column",
    ["M"] = "clear_marks",
    ["fr"] = "filter_to_marked_rows",
    ["fc"] = "filter_to_marked_columns",
    ["fm"] = "filter_to_marked_both",

    ["f"] = "filter",
    ["<BS>"] = "pop_filter",
    ["<leader>fc"] = "clear_filters",

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
    ["<leader>ps"] = "set_page_size",

    ["gs"] = "show_stats",
    ["gi"] = "show_info",
    ["gS"] = "show_sheets",
    ["?"] = "show_help",

    ["<leader>r"] = "refresh",
    ["<leader>x"] = "clear_all",
  },
})
```

A key set to `false` will prevent the default bind without setting a new one.

```lua
keymaps = {
  ["<C-n>"] = "next_column",
  ["<Tab>"] = false,
}
```

## Command

`:CsvTable [path]` opens `path`, or re-opens the current buffer's file. `:edit` on a matching extension does the same thing after the plugin has loaded.

## Statusline

`require("csv-table").status(bufnr)` returns a one-line summary: sheet, rows on screen, active filters and marks, the sort, and the column clipboard. Other buffers return an empty string. Use this for integration with your statusline.

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

| Group               | Default           | Used for                          |
| ------------------- | ----------------- | --------------------------------- |
| `CsvHeader`         | bold `#ededed`    | The header row                    |
| `CsvBorder`         | `#444444`         | The lines the table is drawn with |
| `CsvRowId`          | `CsvBorder`       | The row number in column one      |
| `CsvNumberPositive` | `#85e0b1`         | A positive number                 |
| `CsvNumberNegative` | `#ff8066`         | A negative number                 |
| `CsvDate`           | `#ffd685`         | A date or a time                  |
| `CsvMarkedRow`      | `DiffAdd`         | A row you marked with `m`         |
| `CsvMarkedColumn`   | `DiffText`        | A column you marked with `<M-m>`  |
| `CsvFlash`          | `Visual`          | The brief flash on a moved column |

## Keys

All buffer-local to a table buffer. Hit `?` inside one for the same list.

### Moving

| Key       | Action        | Does                       |
| --------- | ------------- | -------------------------- |
| `<Tab>`   | `next_column` | Move to the next column     |
| `<S-Tab>` | `prev_column` | Move to the previous column |

### Sorting

| Key  | Action              | Does                                              |
| ---- | ------------------- | ------------------------------------------------- |
| `sa` | `sort_asc`          | Sort by this column ascending, or clear that sort  |
| `sd` | `sort_desc`         | Sort by this column descending, or clear that sort |
| `Sa` | `add_sort_key_asc`  | Add this column to the sort, ascending             |
| `Sd` | `add_sort_key_desc` | Add this column to the sort, descending            |
| `ss` | `remove_sort_key`   | Drop this column from the sort                     |
| `sc` | `clear_sort`        | Clear the sort entirely                            |

Sorted columns get an arrow in the header. Sort on several and the arrows are numbered, most significant first.

### Columns

| Key         | Action                 | Does                                       |
|-------------|------------------------|--------------------------------------------|
| `h`         | `hide_column`          | Hide this column                           |
| `x`         | `cut_column`           | Cut this column, replacing the register    |
| `X`         | `cut_append_column`    | Cut this column, appending to the register |
| `p`         | `paste_columns_after`  | Paste the cut column(s) after this one     |
| `P`         | `paste_columns_before` | Paste the cut columns(s) before this one   |
| `<`         | `move_column_left`     | Move this column one place left            |
| `>`         | `move_column_right`    | Move this column one place right           |
| `<leader>X` | `show_all_columns`     | Show all hidden columns again              |

### Marking

| Key     | Action                     | Does                                            |
|---------|----------------------------|-------------------------------------------------|
| `m`     | `toggle_mark_row`          | Mark or unmark this row                         |
| `<M-m>` | `toggle_mark_column`       | Mark or unmark this column                      |
| `M`     | `clear_marks`              | Clear every marked row and column               |
| `fr`    | `filter_to_marked_rows`    | Toggle showing only marked **rows**             |
| `fc`    | `filter_to_marked_columns` | Toggle showing only marked **columns**          |
| `fm`    | `filter_to_marked_both`    | Toggle showing only marked **rows and columns** |

Marks survive filtering and sorting.

### Filtering

| Key          | Action           | Does                        |
| ------------ | ---------------- | --------------------------- |
| `f`          | `filter`         | Filter on this column        |
| `<BS>`       | `pop_filter`     | Drop the filter added last   |
| `<leader>fc` | `clear_filters`  | Drop every filter            |

`f` opens a dialog with comparisons that make sense for the column. Numeric columns get `>`, `>=`, `<`, `<=`, `==` and `!=`. Text columns get equals, not equals, contains, starts with, ends with and regex. Two more options are always available:

- `v` shows the column's distinct values with counts, as a checklist. `<Space>` toggles, `<CR>` applies.
- `e` lets you write a [moonblade](https://github.com/medialab/xan) expression by hand.

Filters are ANDed.

### Formatting

| Key  | Action               | Does                                    |
| ---- | -------------------- | --------------------------------------- |
| `al` | `align_left`         | Align this column left                   |
| `ac` | `align_center`       | Align this column centre                 |
| `ar` | `align_right`        | Align this column right                  |
| `.`  | `increase_precision` | Show one more decimal in this column     |
| `,`  | `decrease_precision` | Show one fewer decimal in this column    |
| `+`  | `increase_width`     | Widen this column by one                 |
| `_`  | `decrease_width`     | Narrow this column by one                |
| `@`  | `set_format`         | Give this column a printf format         |

Numeric columns get a sensible number of decimals automatically, so prices dumped from a float32 read as `199.59` rather than `199.589996338`. These keys override that. Enter nothing at the `@` prompt to revert to the default.

### Paging

| Key          | Action          | Does                                |
| ------------ | --------------- | ----------------------------------- |
| `]`          | `next_page`     | Show the next page                   |
| `[`          | `prev_page`     | Show the previous page               |
| `]]`         | `last_page`     | Show the last page                   |
| `[[`         | `first_page`    | Show the first page                  |
| `<leader>ps` | `set_page_size` | Choose how many rows a page holds    |

`<leader>ps` sets the page size for one buffer. `page_size` sets it for all of them.

### Panels

| Key  | Action        | Does                                    |
|------|---------------|-----------------------------------------|
| `gs` | `show_stats`  | Summarise this column                   |
| `gi` | `show_info`   | Describe this file and the current view |
| `gS` | `show_sheets` | Choose which sheet to read              |
| `?`  | `show_help`   | List every key                          |

`gs` and `gi` respect your current filters. `gS` only applies to workbooks, and switching sheets clears your filters and formats. Panels close with `q` or `<Esc>`.

### Everything else

| Key         | Action      | Does                                          |
|-------------|-------------|-----------------------------------------------|
| `<leader>r` | `refresh`   | Read the file again                           |
| `<leader>x` | `clear_all` | Clear filters, sort, marks and hidden columns |

## License

MIT. See `LICENSE`.
