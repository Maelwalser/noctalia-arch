vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.softtabstop = 2
vim.opt_local.expandtab = true

vim.keymap.set("n", "<leader>tt", "<cmd>!npm test<CR>",
	{ buffer = true, silent = true, desc = "Run NPM Test" })
vim.keymap.set("n", "<leader>tc", "<cmd>!npm test -- --coverage<CR>",
	{ buffer = true, silent = true, desc = "Run NPM Test Coverage" })

-- Error-only diagnostic navigation (generic <leader>gn/gp from on_attach jumps any severity)
vim.keymap.set("n", "<leader>gn", function()
	vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Next error" })
vim.keymap.set("n", "<leader>gp", function()
	vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Previous error" })
