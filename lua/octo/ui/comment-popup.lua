local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local vim = vim

local M = {}

---@class CommentPopup
---@field bufnr integer
---@field winid integer
---@field threads any[]
---@field octo_buffer OctoBuffer
---@field repo string
---@field number integer
---@field side string
---@field path string
local CommentPopup = {}
CommentPopup.__index = CommentPopup

---Create and initialize popup
---@param opts {threads: any[], repo: string, number: integer, side: string, path: string}
---@return CommentPopup
function CommentPopup:new(opts)
  ---@type CommentPopup
  local this = {
    threads = opts.threads,
    repo = opts.repo,
    number = opts.number,
    side = opts.side,
    path = opts.path,
    winid = nil,
  }

  -- Create buffer
  this.bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer name
  local line = this.threads[1].originalStartLine or this.threads[1].originalLine
  if line == vim.NIL or not line then
    line = 0
  end
  line = tonumber(line) or 0
  local bufname = string.format("octo://%s/review/popup/threads/%s%s:%d",
    this.repo, this.side, "/" .. this.path, line)
  vim.api.nvim_buf_set_name(this.bufnr, bufname)

  -- Create OctoBuffer and render
  this.octo_buffer = OctoBuffer:new {
    bufnr = this.bufnr,
    number = this.number,
    repo = this.repo,
  }
  this.octo_buffer:render_threads(this.threads)
  this.octo_buffer:configure()

  setmetatable(this, self)
  return this
end

---Open floating window popup at cursor line
function CommentPopup:open()
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local bufnr = self.bufnr
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  -- Calculate content height (min 3 lines for border)
  local content_height = math.max(3, line_count + 2)
  
  -- Get screen dimensions
  local screen_height = vim.o.lines
  local screen_width = vim.o.columns
  
  -- Get cursor position
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  
  -- Determine if we show above or below
  local space_below = screen_height - cursor_line - 1
  local space_above = cursor_line - 1
  
  local popup_height = math.min(content_height, screen_height - 2)
  local show_above = space_below < popup_height and space_above >= popup_height
  
  -- Position: full width
  -- If showing below: starts at next line (cursor_line)
  -- If showing above: ends at cursor line - 1
  local row = show_above and (cursor_line - popup_height - 1) or cursor_line
  local col = 0
  local width = screen_width

  local win_opts = {
    relative = "cursor",
    width = width,
    height = popup_height,
    row = show_above and -popup_height or 1,
    col = 0,
    border = "rounded",
    style = "minimal",
    zindex = 50,
  }

  self.winid = vim.api.nvim_open_win(self.bufnr, true, win_opts)

  -- Close popup on losing focus
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.bufnr,
    callback = function()
      self:close()
    end,
    once = true,
  })

  -- Set 'q' to close popup
  vim.keymap.set("n", "q", function()
    self:close()
  end, { buffer = self.bufnr, noremap = true })
end

---Close popup and cleanup
function CommentPopup:close()
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

---Check if popup is valid
---@return boolean
function CommentPopup:is_valid()
  return vim.api.nvim_win_is_valid(self.winid) and vim.api.nvim_buf_is_valid(self.bufnr)
end

M.CommentPopup = CommentPopup
return M

