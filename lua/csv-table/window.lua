--[[
Floating windows.

The filter dialog and the panels all want the same thing: some lines of text in
a centered float that closes on `q` or Escape. This is that, and nothing else.

A list to search rather than read goes through `csv-table.picker` instead.
]]

local M = {}

---@param lines string[]
---@return integer
local function max_line_width(lines)
  local width = 0
  for _, line in ipairs(lines) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > width then
      width = line_width
    end
  end
  return width
end

--- How many screen lines `lines` need once wrapped at `width`.
---@param lines string[]
---@param width integer
---@return integer
local function wrapped_height(lines, width)
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(math.ceil(vim.fn.strdisplaywidth(line) / width), 1)
  end
  return height
end

--- Open `lines` in a centered float.
---@param lines string[]
---@param opts { title: string, modifiable: boolean|nil, wrap: boolean|nil }
---@return integer bufnr
---@return integer winid
function M.open(lines, opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = opts.modifiable or false
  vim.bo[bufnr].bufhidden = "wipe"

  local width = math.max(math.min(max_line_width(lines) + 2, vim.o.columns - 8), #opts.title + 6)
  local content_height = opts.wrap and wrapped_height(lines, width) or #lines
  local height = math.max(math.min(content_height, vim.o.lines - 8), 1)

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0),
    col = math.max(math.floor((vim.o.columns - width) / 2), 0),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
  })
  vim.wo[winid][0].wrap = opts.wrap or false
  vim.wo[winid][0].cursorline = true

  M.close_on(bufnr, winid, { "q", "<Esc>" })
  return bufnr, winid
end

--- Close `winid` when any of `keys` is pressed in `bufnr`.
---@param bufnr integer
---@param winid integer
---@param keys string[]
function M.close_on(bufnr, winid, keys)
  for _, key in ipairs(keys) do
    vim.keymap.set("n", key, function()
      M.close(winid)
    end, { buffer = bufnr, nowait = true })
  end
end

---@param winid integer
function M.close(winid)
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
end

return M
