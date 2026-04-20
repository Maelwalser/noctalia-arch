vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4
vim.opt_local.expandtab = false

vim.keymap.set("n", "<leader>tt", "<cmd>!go test -v ./...<CR>",
	{ buffer = true, silent = true, desc = "Go Test Package" })
vim.keymap.set("n", "<leader>tc",
	"<cmd>!go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out<CR>",
	{ buffer = true, silent = true, desc = "Go Test Coverage" })

-- Error-only diagnostic navigation (generic <leader>gn/gp from on_attach jumps any severity)
vim.keymap.set("n", "<leader>gn", function()
	vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Next Go error" })
vim.keymap.set("n", "<leader>gp", function()
	vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Previous Go error" })
