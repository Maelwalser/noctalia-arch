vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4
vim.opt_local.expandtab = true

vim.keymap.set("n", "<leader>pr", function()
	local venv = os.getenv("VIRTUAL_ENV")
	local python_exe = (venv and venv ~= "") and (venv .. "/bin/python") or "python"
	vim.cmd("!" .. python_exe .. " %")
end, { buffer = true, silent = false, desc = "Python Run File" })
