-- Claude Code hands its prompt to $EDITOR (ctrl+g in the chat input) as
-- $TMPDIR/claude-prompt-<id>.md. When that file is opened here, the session's
-- conversation is rendered with `claude-transcript` and shown read-only in a
-- split above the prompt, so the history can be scrolled, searched and yanked
-- from with normal motions. <C-k> moves up into it, <C-j> back to the prompt;
-- :wq on the prompt returns the text to Claude as usual.
--
--   <leader>ch   toggle the history split (prompt and history buffers)
--   <leader>cf   reload the history with tool calls and results in full
--   q            close the history split (history buffer)

local M = {}

local group = vim.api.nvim_create_augroup("ClaudePrompt", { clear = true })
local HISTORY_SHARE = 0.7 -- of the screen height given to the history split

local state = { win = nil, buf = nil, full = false }

local function history_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function close_history()
  if history_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

local function transcript_bin()
  if vim.fn.executable("claude-transcript") == 1 then
    return "claude-transcript"
  end
  -- Not on PATH when the terminal was spawned outside a login shell.
  local stowed = vim.fn.expand("~/.local/bin/claude-transcript")
  if vim.fn.executable(stowed) == 1 then
    return stowed
  end
  return nil
end

local function render(full)
  local bin = transcript_bin()
  if not bin then
    return nil, "claude-transcript not found (stow the dotfiles' claude package)"
  end
  local cmd = { bin }
  if full then
    table.insert(cmd, "--full")
  end
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(lines, " ")
  end
  return lines
end

local function fill(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function history_keymaps(buf, prompt_win)
  local opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "q", close_history, vim.tbl_extend("force", opts, { desc = "close Claude history" }))
  vim.keymap.set("n", "<leader>ch", close_history, vim.tbl_extend("force", opts, { desc = "close Claude history" }))
  vim.keymap.set("n", "<leader>cf", function()
    M.reload(prompt_win, not state.full)
  end, vim.tbl_extend("force", opts, { desc = "toggle full Claude history" }))
  vim.keymap.set("n", "R", function()
    M.reload(prompt_win, state.full)
  end, vim.tbl_extend("force", opts, { desc = "reload Claude history" }))
end

--- Re-render the history buffer in place, keeping the window.
function M.reload(prompt_win, full)
  if not history_open() then
    return M.open(prompt_win, full)
  end
  local lines, err = render(full)
  if not lines then
    vim.notify("Claude history: " .. err, vim.log.levels.ERROR)
    return
  end
  state.full = full
  fill(state.buf, lines)
  vim.api.nvim_win_call(state.win, function()
    vim.cmd("normal! G")
  end)
end

--- Open the history split above `prompt_win` and return focus to the prompt.
function M.open(prompt_win, full)
  if history_open() then
    close_history()
    return
  end
  local lines, err = render(full)
  if not lines then
    vim.notify("Claude history: " .. err, vim.log.levels.ERROR)
    return
  end
  state.full = full

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "claude://history")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  fill(buf, lines)
  vim.bo[buf].filetype = "markdown"
  state.buf = buf

  local win = vim.api.nvim_open_win(buf, true, {
    split = "above",
    win = prompt_win,
    height = math.max(5, math.floor(vim.o.lines * HISTORY_SHARE)),
  })
  state.win = win
  for opt, val in pairs({
    wrap = true,
    linebreak = true,
    spell = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldenable = false,
    cursorline = true,
  }) do
    vim.wo[win][opt] = val
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! G")
  end)
  history_keymaps(buf, prompt_win)

  if vim.api.nvim_win_is_valid(prompt_win) then
    vim.api.nvim_set_current_win(prompt_win)
  end
end

local function setup_prompt(buf)
  if vim.b[buf].claude_prompt then
    return
  end
  vim.b[buf].claude_prompt = true
  local prompt_win = vim.api.nvim_get_current_win()

  vim.keymap.set("n", "<leader>ch", function()
    M.open(prompt_win, state.full)
  end, { buffer = buf, silent = true, desc = "toggle Claude history" })
  vim.keymap.set("n", "<leader>cf", function()
    M.reload(prompt_win, not state.full)
  end, { buffer = buf, silent = true, desc = "toggle full Claude history" })

  -- Quitting the prompt must end the editor session, or Claude keeps waiting.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = buf,
    callback = close_history,
  })

  -- Defer so the markdown ftplugin and render-markdown have run for the prompt.
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(prompt_win) and vim.api.nvim_win_get_buf(prompt_win) == buf then
      M.open(prompt_win, false)
      vim.api.nvim_win_call(prompt_win, function()
        vim.cmd("normal! G$")
      end)
    end
  end)
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  pattern = "*/claude-prompt-*.md",
  callback = function(ev)
    setup_prompt(ev.buf)
  end,
})

return M
