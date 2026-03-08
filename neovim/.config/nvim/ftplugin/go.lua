vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4
vim.opt_local.expandtab = false

-- Example: Keymap to run go tests in the current package
vim.keymap.set("n", "<leader>tt", "<cmd>!go test -v ./...<CR>",
    { buffer = true, noremap = true, silent = true, desc = "Go Test Package" })
vim.keymap.set("n", "<leader>tc",
    "<cmd>!go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out<CR>",
    { buffer = true, noremap = true, silent = true, desc = "Go Test Coverage" })

local function jump_to_error(count)
    -- Use vim.diagnostic.jump (Nvim 0.10+) if available, otherwise fallback
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

vim.keymap.set({ "n", "v" }, "<leader>ga", vim.lsp.buf.code_action, { buffer = true, desc = "LSP Code Action" })

vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { buffer = true, desc = "LSP Code Action" })

vim.keymap.set('n', '<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
end, { buffer = true, desc = "LSP Code Action" })

vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { buffer = true, desc = "LSP Code Action" })
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = true, desc = "LSP Code Action" })

vim.keymap.set('n', '<leader>gr', vim.lsp.buf.references, { buffer = true, desc = "LSP Code Action" })
vim.keymap.set('n', '<leader>rr', vim.lsp.buf.rename, { buffer = true, desc = "LSP Code Action" })
