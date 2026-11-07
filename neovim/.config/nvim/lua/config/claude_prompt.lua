-- Claude Code hands its prompt to $EDITOR (ctrl+g in the chat input) as
-- $TMPDIR/claude-prompt-<id>.md. When that file is opened here, the session's
-- conversation is rendered with `claude-transcript` and shown read-only in a
-- split above the prompt, so the history can be scrolled, searched and yanked
-- from with normal motions. <C-k> moves up into it, <C-j> back to the prompt;
-- :wq on the prompt returns the text to Claude as usual.
--
-- Both windows wrap long lines flush with the left edge and show no
-- breadcrumb winbar or pinned headings: a chat is not a source file. The
-- history is hard-wrapped to its window width (and re-wrapped on resize), so
-- every screen row is a real line and j, k, V and yanks behave as in code.
--
--   <leader>ch   toggle the history split (prompt and history buffers)
--   <leader>cf   reload the history with tool calls and results in full
--
-- In the history buffer every turn is a fold (your prompts hold Claude's
-- replies), so collapsing everything leaves one line per prompt:
--
--   ]] / [[      next / previous turn            ]u / [u   next / previous prompt
--   <Tab>        fold or unfold the turn under the cursor
--   <S-Tab>      collapse every prompt to one line, or expand them all
--   go           pick a turn from a list and jump to it
--   R            re-render the history            q         close the split

local M = {}

local group = vim.api.nvim_create_augroup("ClaudePrompt", { clear = true })
local HISTORY_SHARE = 0.7 -- of the screen height given to the history split
local TURN = [[^##\{1,2} ]] -- a turn heading: `## ▲ You` or `### ◆ Claude`
local PROMPT = [[^## ]] -- a prompt heading (also compaction summaries)

local state = { win = nil, buf = nil, full = false, prompts = 0, raw = nil, width = nil }

-- True while the history buffer is shown; if the tracked window went away
-- (:only from a split of it, say) another window showing it is adopted.
local function history_open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return true
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    state.win = vim.fn.win_findbuf(state.buf)[1]
    return state.win ~= nil
  end
  return false
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

-- Break one paragraph line into lines of at most `width` cells, continuing
-- under a list marker or quote prefix. Runs of spaces collapse to one.
local function wrap_paragraph(line, width)
  local indent, rest = line:match("^(%s*)(.*)$")
  local marker = rest:match("^([-*+] )") or rest:match("^(%d+[.)] )") or rest:match("^(> )") or ""
  local hang = indent .. string.rep(" ", #marker)
  local out = {}
  local cur, curw, first = indent .. marker, nil, true
  curw = vim.fn.strdisplaywidth(cur)
  for word in rest:sub(#marker + 1):gmatch("%S+") do
    local ww = vim.fn.strdisplaywidth(word)
    if not first and curw + 1 + ww > width then
      table.insert(out, cur)
      cur, curw = hang .. word, vim.fn.strdisplaywidth(hang) + ww
    else
      cur = first and (cur .. word) or (cur .. " " .. word)
      curw = curw + (first and 0 or 1) + ww
    end
    first = false
  end
  table.insert(out, cur)
  return out
end

-- Hard-wrap the prose of a transcript; headings, table rows and fenced code
-- are kept as they are.
local function wrap_lines(lines, width)
  local out, fenced = {}, false
  for _, line in ipairs(lines) do
    if line:match("^%s*```") then
      fenced = not fenced
      table.insert(out, line)
    elseif fenced or line:match("^#") or line:match("^%s*|") or vim.fn.strdisplaywidth(line) <= width then
      table.insert(out, line)
    else
      vim.list_extend(out, wrap_paragraph(line, width))
    end
  end
  return out
end

local function text_width(win)
  return math.max(20, vim.api.nvim_win_get_width(win) - 1)
end

local function fill(buf, win, lines)
  state.raw = lines
  state.width = text_width(win)
  -- strdisplaywidth() measures with the current window's options.
  local wrapped = vim.api.nvim_win_call(win, function()
    return wrap_lines(lines, state.width)
  end)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  state.prompts = 0
  for _, line in ipairs(lines) do
    if line:match("^## ▲") then
      state.prompts = state.prompts + 1
    end
  end
end

-- Re-wrap after the window changed width, keeping the view at the bottom
-- when it was there.
local function rewrap()
  if not history_open() or state.width == text_width(state.win) then
    return
  end
  local at_end = vim.api.nvim_win_get_cursor(state.win)[1] == vim.api.nvim_buf_line_count(state.buf)
  fill(state.buf, state.win, state.raw)
  if at_end then
    vim.api.nvim_win_call(state.win, function()
      vim.cmd("normal! G")
    end)
  end
end

vim.api.nvim_create_autocmd("WinResized", {
  group = group,
  callback = function()
    if history_open() and vim.tbl_contains(vim.v.event.windows, state.win) then
      rewrap()
    end
  end,
})

-- Wrapped lines continue at the left edge rather than indented under an arrow,
-- and no breadcrumb is drawn: chat text has no directory or symbol to show.
local function chat_window(win)
  for opt, val in pairs({
    wrap = true,
    linebreak = true,
    breakindent = false,
    winbar = "",
  }) do
    vim.wo[win][opt] = val
  end
  -- An empty window-local 'showbreak' falls back to the global arrow; NONE is
  -- the sentinel that keeps it empty.
  vim.api.nvim_win_call(win, function()
    vim.cmd("setlocal showbreak=NONE")
  end)
end

-- barbecue redraws its breadcrumb on every cursor hold and window event for
-- any file buffer; it has no per-buffer switch, so its updater is wrapped to
-- leave prompt windows alone.
local barbecue_patched = false
local function silence_barbecue()
  if barbecue_patched then
    return
  end
  local ok, ui = pcall(require, "barbecue.ui")
  if not ok then
    return
  end
  barbecue_patched = true
  local update = ui.update
  ui.update = function(winnr)
    winnr = winnr or vim.api.nvim_get_current_win()
    if vim.b[vim.api.nvim_win_get_buf(winnr)].claude_prompt then
      vim.wo[winnr].winbar = ""
      return
    end
    return update(winnr)
  end
end

local function heading_lines(buf)
  local turns = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^##+ ") then
      table.insert(turns, { lnum = lnum, text = line:gsub("^#+%s*", "") })
    end
  end
  return turns
end

-- First line of a turn's body, for fold text and the picker.
local function first_body_line(buf, from, to)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, from, to, false)) do
    if line ~= "" and not line:match("^#") and not line:match("^```") then
      return line
    end
  end
  return ""
end


--- 'foldtext' for the history: the turn heading followed by its first line,
--- so a fully folded history reads as a list of prompts.
function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local first, last = vim.v.foldstart, vim.v.foldend
  local head = vim.fn.getline(first)
  local label = head:match("^#+%s*(.*)") or head
  local body = first_body_line(buf, first, last)
  local width = vim.api.nvim_win_get_width(0) - #label - 16
  if width > 8 and #body > width then
    body = body:sub(1, width - 1) .. "…"
  end
  local lines = last - first + 1
  return string.format("%s   %s   (%d lines)", label, body, lines)
end

local function jump(pattern, backwards, what)
  local flags = backwards and "bW" or "W"
  if vim.fn.search(pattern, flags) == 0 then
    vim.notify("Claude history: no " .. (backwards and "earlier " or "later ") .. what, vim.log.levels.INFO)
  end
end

-- Level 1 keeps the session title open and closes every prompt section
-- beneath it, so the window becomes one fold line per prompt.
local function toggle_all(win)
  if vim.wo[win].foldlevel <= 1 then
    vim.wo[win].foldlevel = 99
  else
    vim.wo[win].foldlevel = 1
  end
end

local function pick_turn(buf, win)
  local turns = heading_lines(buf)
  if #turns == 0 then
    return
  end
  for i, turn in ipairs(turns) do
    local stop = turns[i + 1] and turns[i + 1].lnum - 1 or vim.api.nvim_buf_line_count(buf)
    turn.body = first_body_line(buf, turn.lnum, stop)
  end
  vim.ui.select(turns, {
    prompt = "Claude history",
    format_item = function(turn)
      return string.format("%-22s %s", turn.text, turn.body)
    end,
  }, function(turn)
    if turn and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { turn.lnum, 0 })
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zt")
      end)
    end
  end)
end

local function history_keymaps(buf, win, prompt_win)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map("q", close_history, "close Claude history")
  map("<leader>ch", close_history, "close Claude history")
  map("<leader>cf", function()
    M.reload(prompt_win, not state.full)
  end, "toggle full Claude history")
  map("R", function()
    M.reload(prompt_win, state.full)
  end, "reload Claude history")
  map("]]", function()
    jump(TURN, false, "turn")
  end, "next turn")
  map("[[", function()
    jump(TURN, true, "turn")
  end, "previous turn")
  map("]u", function()
    jump(PROMPT, false, "prompt")
  end, "next prompt")
  map("[u", function()
    jump(PROMPT, true, "prompt")
  end, "previous prompt")
  map("<Tab>", "za", "fold or unfold this turn")
  map("<S-Tab>", function()
    toggle_all(win)
  end, "collapse or expand every turn")
  map("go", function()
    pick_turn(buf, win)
  end, "pick a turn")
end

local HINTS = {
  "]] [[ turn   ]u [u prompt   ⇥ fold   go list   q close ",
  "⇥ fold   go list   q close ",
  "q close ",
}

--- 'winbar' of the history window: what is shown on the left, and on the
--- right as many key hints as the window is wide enough for. A `%{%` item is
--- evaluated with the drawn window current (g:statusline_winid is only set
--- for `%!` expressions).
function M.winbar()
  local win = vim.api.nvim_get_current_win()
  if not history_open() or win ~= state.win then
    return ""
  end
  local left = string.format(
    " ◆ Claude history · %d prompt%s · %s",
    state.prompts,
    state.prompts == 1 and "" or "s",
    state.full and "full" or "chat"
  )
  local room = vim.api.nvim_win_get_width(win) - vim.fn.strdisplaywidth(left) - 2
  for _, hints in ipairs(HINTS) do
    if vim.fn.strdisplaywidth(hints) <= room then
      return left .. "%=" .. hints
    end
  end
  return left
end

local WINBAR = "%{%v:lua.require('config.claude_prompt').winbar()%}"

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
  fill(state.buf, state.win, lines)
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
  state.buf = buf

  local win = vim.api.nvim_open_win(buf, true, {
    split = "above",
    win = prompt_win,
    height = math.max(5, math.floor(vim.o.lines * HISTORY_SHARE)),
  })
  state.win = win
  chat_window(win)
  fill(buf, win, lines)
  vim.bo[buf].filetype = "markdown"
  for opt, val in pairs({
    spell = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    cursorline = true,
    -- Markdown sections fold with the tree-sitter 'foldexpr' set globally;
    -- every turn starts open, <Tab> and <S-Tab> close them.
    foldenable = true,
    foldmethod = "expr",
    foldlevel = 99,
    foldminlines = 0,
    foldtext = "v:lua.require('config.claude_prompt').foldtext()",
  }) do
    vim.wo[win][opt] = val
  end
  vim.wo[win].winbar = WINBAR
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! G")
  end)
  history_keymaps(buf, win, prompt_win)

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
  silence_barbecue()

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
      chat_window(prompt_win)
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
