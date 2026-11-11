-- Also applies to C++: Neovim's runtime ftplugin/cpp.vim sources ftplugin/c.lua.

vim.keymap.set("n", "<leader>gh", "<cmd>LspClangdSwitchSourceHeader<CR>",
	{ buffer = true, silent = true, desc = "Switch source/header (clangd)" })

-- Error-only diagnostic navigation (generic <leader>gn/gp from on_attach jumps any severity,
-- which with clang-tidy enabled means stopping on every style warning)
vim.keymap.set("n", "<leader>gn", function()
	vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Next C/C++ error" })
vim.keymap.set("n", "<leader>gp", function()
	vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { buffer = true, desc = "Previous C/C++ error" })
