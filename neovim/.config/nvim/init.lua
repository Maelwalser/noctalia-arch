vim.loader.enable()

-- -----------------------------------------------------------------------------
-- UI & APPEARANCE
-- -----------------------------------------------------------------------------
vim.opt.termguicolors = true -- Enable 24-bit RGB colors
vim.opt.syntax = "on"        -- Enable syntax highlighting
vim.opt.guicursor =
"n-v-c:block-blinkon0,i:block-blinkwait700-blinkoff400-blinkon250-Cursor,ci-ve:ver25-blinkon0,r-cr:hor20-blinkon0,o:hor50-blinkon0,sm:block-blinkwait175-blinkoff150-blinkon175"
vim.o.background = "dark"                         -- Set background to dark
vim.opt.guifont = "JetBrainsMonoNL Nerd Font:h12" -- Set editor font

-- Line numbers and wrapping
vim.wo.wrap = false          -- Disable line wrapping
vim.wo.number = true         -- Show line numbers
vim.wo.relativenumber = true -- Show relative line numbers
vim.opt.numberwidth = 2      -- Minimal number of columns for the line number

-- Display
vim.opt.scrolloff = 8 -- Number of screen lines to keep above and below the cursor
vim.opt.sidescrolloff = 8 -- Number of screen columns to keep to the left and right of the cursor
vim.opt.showmode = false -- Don't show mode in command line (already in statusline)
vim.opt.cursorline = true -- Highlight current line
vim.opt.pumheight = 10 -- Maximum number of items to show in popup menu
vim.opt.showcmd = false -- Show (partial) command in the last line of the screen
vim.opt.cmdheight = 0 -- Command line height (0 hides it, 1 is default)
vim.opt.laststatus = 3 -- Global statusline
vim.opt.display = "lastline" -- Show incomplete last line if it fits
vim.opt.title = true -- Set terminal title
vim.opt.fillchars.eob = " " -- Remove ugly ~ from end of buffer
vim.opt.list = true -- Show invisible characters (tabs, trailing whitespace)
vim.opt.showbreak = "↳" -- Character to show before wrapped lines

-- -----------------------------------------------------------------------------
-- LEADER KEYS
-- -----------------------------------------------------------------------------
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- -----------------------------------------------------------------------------
-- TEXT EDITING & INDENTATION
-- -----------------------------------------------------------------------------
-- Search
vim.opt.ignorecase = true -- Ignore case when searching
vim.opt.smartcase = true  -- But not if string contains uppercase letters
vim.opt.hlsearch = true   -- Highlight search results
vim.opt.incsearch = true  -- Show search results incrementally

-- Indentation
vim.opt.expandtab = true           -- Use spaces instead of tabs
vim.opt.shiftwidth = 2             -- Number of spaces to use for autoindent
vim.opt.tabstop = 2                -- Number of spaces that a tab in the file counts for
vim.opt.softtabstop = 2            -- Number of spaces that a tab counts for while performing editing operations
vim.opt.autoindent = true          -- Copy indent from current line when starting a new line
vim.opt.smartindent = true         -- Make indenting smarter
vim.opt.breakindent = true         -- Preserve indentation of wrapped lines
vim.opt.breakindentopt = "shift:2" -- How to indent wrapped lines
vim.opt.shiftround = true          -- Round indent to multiple of 'shiftwidth'

-- Completion
vim.opt.completeopt = "menuone,noselect" -- Completion options
vim.opt.shortmess:append "c"             -- Don't pass messages to |ins-completion-menu|

-- Backspace
vim.opt.backspace = "indent,eol,start" -- Allow backspace over autoindent, EOL, start of insert
--
-- Clipboard
vim.opt.clipboard:append("unnamedplus")


-- Other
vim.opt.iskeyword:append "-"  -- Treat hyphenated words as single words
vim.opt.isfname:append("@-@") -- Characters to be included in filenames

-- -----------------------------------------------------------------------------
-- FILES, BACKUP & SESSIONS
-- -----------------------------------------------------------------------------
vim.opt.backup = false                                -- No backup files
vim.opt.writebackup = false                           -- No backup before overwriting files
vim.opt.swapfile = false                              -- No swap files
vim.opt.undofile = true                               -- Enable persistent undo
vim.opt.undodir = vim.fn.stdpath "data" .. "/undodir" -- Set undo directory
vim.opt.hidden = true                                 -- Allow modified buffers to be hidden without saving
vim.opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- -----------------------------------------------------------------------------
-- BUFFERS & WINDOWS
-- -----------------------------------------------------------------------------
vim.opt.splitbelow = true            -- When splitting, new window appears below current window
vim.opt.splitright = true            -- When splitting, new window appears to the right of current window
vim.opt.viewoptions:remove "options" -- Make viewoptions more minimal (e.g., for :mkview)

-- ----------------------------------------------------------------------------- FOLDING
-- -----------------------------------------------------------------------------
vim.opt.foldenable = false                      -- Disable folding by default
vim.opt.foldlevel = 99                          -- Keep folds open by default
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()" -- Utilize Treesitter folds
vim.opt.conceallevel = 2                        -- Hide concealed text (e.g. markdown formatting)

-- -----------------------------------------------------------------------------
-- DIAGNOSTICS & LSP
-- -----------------------------------------------------------------------------
vim.diagnostic.config({
	float = { border = "rounded" }, -- Add border to diagnostic popups
    underline = {
        severity = vim.diagnostic.severity.WARN,
    },
})

-- -----------------------------------------------------------------------------
-- TIMINGS & BEHAVIOR
-- -----------------------------------------------------------------------------
vim.opt.updatetime = 100 -- Time in ms to wait before triggering CursorHold
vim.opt.timeoutlen = 300 -- Time in ms to wait for a mapped sequence to complete
vim.opt.ttimeoutlen = 50 -- Time to wait for a key code sequence (default 50ms)
vim.opt.mouse = ""       -- Disable mouse
-- -----------------------------------------------------------------------------
-- SYSTEM & ENCODING
-- -----------------------------------------------------------------------------
-- Language and encoding
vim.cmd [[
  language en_US.UTF-8
]]
vim.opt.fileencoding = "utf-8" -- File encoding



-- Performance related options
-- vim.opt.lazyredraw = true -- Don't redraw while executing macros (good for performance)
-- vim.opt.fsync = false -- Disable fsync for better performance on some systems (use with caution if power loss is a concern)

-- Disable some default providers if alternatives are used
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1


-- Create an augroup named "YankHighlight", clearing any existing one with the same name
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })

-- Create an autocommand for the "TextYankPost" event (after text is yanked)
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		vim.highlight.on_yank()
	end,
	group = highlight_group,
	pattern = "*",
})

-- --------------------------------------------------------
-- KEYMAPS
-- --------------------------------------------------------

-- CLEAR SEARCH HIGHLIGHTS
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Remove search highlights" })
--
-- SEARCH RESULT NAVIGATION (Alt + n for next, Alt + p for previous)
vim.keymap.set("n", "<C-n>", "n", { desc = "Next search result" })
vim.keymap.set("n", "<C-p>", "N", { desc = "Previous search result" })

-- EXIT TERMINAL MODE
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit Terminal mode" })
--
-- GITLEAKS
vim.keymap.set("n", "<leader>gS", function()
	vim.cmd("split | term gitleaks detect -v --source .")
end, { desc = "(G)it (S)can for leaks" })
-- FILES SAVING & QUITTING
vim.keymap.set("n", "<leader>wq", ":wq<CR>", { desc = "save and quit" })
vim.keymap.set("n", "<leader>qq", ":q!<CR>", { desc = "quit without save" })
vim.keymap.set("n", "<leader>ww", ":w<CR>", { desc = "save" })

-- Moving through paragraphs
vim.keymap.set("n", "<Leader>j", "}", { desc = "Move to next paragraph" })
vim.keymap.set("n", "<Leader>k", "{", { desc = "Move to previous paragraph" })

-- Moving through paragraphs
vim.keymap.set("n", "<Leader>h", "0", { desc = "Move to end of line" })
vim.keymap.set("n", "<Leader>l", "$", { desc = "Move to beginning of line" })

-- TAB MANAGEMENT
vim.keymap.set("n", "<leader>to", ":tabnew<CR>")   -- open a new tab
vim.keymap.set("n", "<leader>tx", ":tabclose<CR>") -- close a tab
vim.keymap.set("n", "<leader>tn", ":tabn<CR>")     -- next tab
vim.keymap.set("n", "<leader>tp", ":tabp<CR>")     -- previous tab

-- QUICKFIX KEYMAPS
vim.keymap.set("n", "<leader>qo", ":copen<CR>")  -- open quickfix list
vim.keymap.set("n", "<leader>qf", ":cfirst<CR>") -- jump to first quickfix list item
vim.keymap.set("n", "<leader>qn", ":cnext<CR>")  -- jump to next quickfix list item
vim.keymap.set("n", "<leader>qp", ":cprev<CR>")  -- jump to prev quickfix list item
vim.keymap.set("n", "<leader>ql", ":clast<CR>")  -- jump to last quickfix list item
vim.keymap.set("n", "<leader>qx", ":cclose<CR>") -- close quickfix list

-- VIM REST CONSOLE
-- vim.keymap.set("n", "<leader>xr", ":call VrcQuery()<CR>") -- Run REST query

-- SPLIT WINDOW
vim.keymap.set("n", "<leader>wv", ":vsplit<cr>", { desc = "[W]indow Split [V]ertical" })
vim.keymap.set("n", "<leader>wh", ":split<cr>", { desc = "[W]indow Split [H]orizontal" })
vim.keymap.set("n", "<leader>we", "<C-w>=", { desc = "[W]indow Split Equal WIdth" })
vim.keymap.set("n", "<leader>wx", ":close<CR>", { desc = "Close split [W]indow" })
vim.keymap.set("n", "<leader>wj", "<C-w>-", { desc = "make split [W]indow height shorter" }) -- make split window height shorter
vim.keymap.set("n", "<leader>wk", "<C-w>+", { desc = "make split [W]indow height taller" })  -- make split windows height taller
vim.keymap.set("n", "<leader>wl", "<C-w>>5", { desc = "make split [W]indow width bigger" }) -- make split windows width bigger
-- STAY IN INDENT MODE
vim.keymap.set("v", "<", "<gv", { desc = "Indent left in visual mode" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right in visual mode" })

-- OIL
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

vim.keymap.set("n", "<leader>fm", function()
	require("telescope.builtin").treesitter({ symbols = { "function", "method" } })
end)

-- DIAGNOSTIC (Keymaps moved to nvim-lspconfig on_attach)
-- Debugging
vim.keymap.set("n", "<leader>bb", "<cmd>lua require'dap'.toggle_breakpoint()<cr>")
vim.keymap.set("n", "<leader>bc", "<cmd>lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<cr>")
vim.keymap.set(
	"n",
	"<leader>bl",
	"<cmd>lua require'dap'.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))<cr>"
)
vim.keymap.set("n", "<leader>br", "<cmd>lua require'dap'.clear_breakpoints()<cr>")
vim.keymap.set("n", "<leader>ba", "<cmd>Telescope dap list_breakpoints<cr>")
vim.keymap.set("n", "<leader>dc", "<cmd>lua require'dap'.continue()<cr>")
vim.keymap.set("n", "<leader>dj", "<cmd>lua require'dap'.step_over()<cr>")
vim.keymap.set("n", "<leader>dk", "<cmd>lua require'dap'.step_into()<cr>")
vim.keymap.set("n", "<leader>do", "<cmd>lua require'dap'.step_out()<cr>")
vim.keymap.set("n", "<leader>dd", function()
	require("dap").disconnect()
	require("dapui").close()
end)
vim.keymap.set("n", "<leader>dt", function()
	require("dap").terminate()
	require("dapui").close()
end)
vim.keymap.set("n", "<leader>dr", "<cmd>lua require'dap'.repl.toggle()<cr>")
vim.keymap.set("n", "<leader>dl", "<cmd>lua require'dap'.run_last()<cr>")
vim.keymap.set("n", "<leader>di", function()
	require("dap.ui.widgets").hover()
end)
vim.keymap.set("n", "<leader>d?", function()
	local widgets = require("dap.ui.widgets")
	widgets.centered_float(widgets.scopes)
end)
vim.keymap.set("n", "<leader>df", "<cmd>Telescope dap frames<cr>")
vim.keymap.set("n", "<leader>dh", "<cmd>Telescope dap commands<cr>")
vim.keymap.set("n", "<leader>de", function()
	require("telescope.builtin").diagnostics({ default_text = ":E:" })
end)

require("config.lazy")


-- Enable spell checking for markdown and text files
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.md", "*.txt" },
	command = "setlocal spell",
})

-- Auto-resize splits when Neovim window is resized
vim.api.nvim_create_autocmd("VimResized", {
	pattern = "*",
	command = "wincmd =",
})


-- Macro recording indicator
vim.fn.sign_define("MacroRecording", { text = "●", texthl = "MacroRecording" })
vim.api.nvim_set_hl(0, "MacroRecording", { fg = "red" })

local macro_recording_group = vim.api.nvim_create_augroup("MacroRecording", { clear = true })
vim.api.nvim_create_autocmd("RecordingEnter", {
	group = macro_recording_group,
	pattern = "*",
	callback = function()
		vim.fn.sign_place(1, "MacroRecording", "MacroRecording", vim.api.nvim_get_current_buf(), { lnum = vim.fn.line("."), priority = 100 })
	end,
})

vim.api.nvim_create_autocmd("RecordingLeave", {
	group = macro_recording_group,
	pattern = "*",
	callback = function()
		vim.fn.sign_unplace("MacroRecording")
	end,
})


