
-- 1. Standard JS/TS Formatting Variables
vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.softtabstop = 2
vim.opt_local.expandtab = true

-- 2. Test Execution Abstractions
-- Hypothesis: Your project utilizes standard npm scripts for testing.
vim.keymap.set("n", "<leader>tt", "<cmd>!npm test<CR>",
    { buffer = true, noremap = true, silent = true, desc = "Run NPM Test" })
    
-- Note: The '--' passes the coverage flag down to the underlying test runner (e.g., Jest/Vitest)
vim.keymap.set("n", "<leader>tc", "<cmd>!npm test -- --coverage<CR>",
    { buffer = true, noremap = true, silent = true, desc = "Run NPM Test Coverage" })

-- 3. Strict Diagnostic Navigation (Error Only)
local function jump_to_error(count)
    if vim.diagnostic.jump then
        vim.diagnostic.jump({ count = count, severity = vim.diagnostic.severity.ERROR, float = true })
    else
        -- Fallback for Neovim 0.9 and older
        local opts = { severity = vim.diagnostic.severity.ERROR, float = true }
        if count > 0 then
            vim.diagnostic.goto_next(opts)
        else
            vim.diagnostic.goto_prev(opts)
        end
    end
end

vim.keymap.set("n", "<leader>gn", function() jump_to_error(1) end, { buffer = true, desc = "Go to next Error" })
vim.keymap.set("n", "<leader>gp", function() jump_to_error(-1) end, { buffer = true, desc = "Go to previous Error" })

-- 4. LSP Code Actions
vim.keymap.set({ "n", "v" }, "<leader>ga", vim.lsp.buf.code_action, { buffer = true, desc = "LSP Code Action" })
