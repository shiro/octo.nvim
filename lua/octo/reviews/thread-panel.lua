local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local utils = require "octo.utils"
local vim = vim

local M = {}

---Show review threads at cursor (triggered by keybind)
function M.show_review_threads()
  -- Check if we are in a diff buffer
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    return
  end

  local review = require("octo.reviews").get_current_review()
  if not review then
    return
  end

  local file = review.layout:get_current_file()
  if not file then
    return
  end

  local pr = file.pull_request
  local review_level = review:get_level()
  ---@type octo.ReviewThread[]
  local threads = vim.tbl_values(review.threads)
  local line = vim.api.nvim_win_get_cursor(0)[1]

  -- Get threads at current line
  local threads_at_cursor = {}
  for _, thread in ipairs(threads) do
    if
      review_level == "PR"
      and utils.is_thread_placed_in_buffer(thread, bufnr)
      and thread.startLine <= line
      and thread.line >= line
    then
      table.insert(threads_at_cursor, thread)
    elseif review_level == "COMMIT" then
      for _, comment in ipairs(thread.comments.nodes) do
        if
          review.layout.right.commit == comment.originalCommit.oid
          and utils.is_thread_placed_in_buffer(thread, bufnr)
          and thread.originalLine == line
        then
          table.insert(threads_at_cursor, thread)
          break
        end
      end
    end
  end

  if #threads_at_cursor > 0 then
    local popup = require("octo.ui.comment-popup").CommentPopup:new {
      threads = threads_at_cursor,
      repo = pr.repo,
      number = pr.number,
      side = split,
      path = file.path,
    }
    popup:open()
    if file.current_popup then
      file.current_popup:close()
    end
    file.current_popup = popup
  else
    utils.info "No review threads on this line"
  end
end

---@param split OctoSplit
---@param file FileEntry
function M.hide_thread_buffer(split, file)
  local alt_buf = file:get_alternative_buf(split)
  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) and vim.api.nvim_buf_is_valid(alt_buf) then
    local current_alt_bufnr = vim.api.nvim_win_get_buf(alt_win)
    if current_alt_bufnr ~= alt_buf then
      -- if we are not showing the corresponding alternative diff buffer, do so
      vim.api.nvim_win_set_buf(alt_win, alt_buf)

      -- Save cursor position before show_diff (which scrolls to sync windows)
      local current_win = vim.api.nvim_get_current_win()
      local cursor_pos = vim.api.nvim_win_get_cursor(current_win)

      -- show the diff
      file:show_diff()

      -- Restore cursor position (show_diff scrolls which can disrupt cursor)
      if vim.api.nvim_win_is_valid(current_win) then
        pcall(vim.api.nvim_win_set_cursor, current_win, cursor_pos)
      end
    end
  end
end

---Create a thread buffer
---@param threads ReviewThread[]
---@param repo string
---@param number integer
---@param side string
---@param path string
---@return OctoBuffer | nil
function M.create_thread_buffer(threads, repo, number, side, path)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    return
  end

  if not vim.startswith(path, "/") then
    path = "/" .. path
  end
  local line = threads[1].originalStartLine ~= vim.NIL and threads[1].originalStartLine or threads[1].originalLine
  local bufname = string.format("octo://%s/review/%s/threads/%s%s:%d", repo, current_review.id, side, path, line)
  local existing_bufnr = vim.fn.bufnr(bufname)

  if existing_bufnr ~= -1 then
    if vim.api.nvim_buf_is_loaded(existing_bufnr) then
      return octo_buffers[existing_bufnr]
    end

    -- Weird situation, force delete buffer and start from scratch
    vim.api.nvim_buf_delete(existing_bufnr, { force = true })
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, bufname)
  local buffer = OctoBuffer:new {
    bufnr = bufnr,
    number = number,
    repo = repo,
  }
  buffer:render_threads(threads)
  buffer:render_signs()
  vim.api.nvim_buf_call(bufnr, function()
    utils.clear_history()
  end)
  return buffer
end

return M
