vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4
vim.opt_local.expandtab = true

-- Keymap for running the current file with the venv python
vim.keymap.set("n", "<leader>pr", function()
  local venv_python = os.getenv("VIRTUAL_ENV")
  local python_exe = "python"
  if venv_python and venv_python ~= "" then
    python_exe = venv_python .. "/bin/python"
  end
  vim.cmd("!" .. python_exe .. " %")
end, { buffer = true, noremap = true, silent = false, desc = "Python Run File" })

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserPythonLspConfig", {}),
  pattern = "*.py",
  callback = function(ev)
    local opts = { buffer = ev.buf, desc = "LSP Code Action" }
    vim.keymap.set({ "n", "v" }, "<leader>ga", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>gn", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, { buffer = ev.buf, desc = "Go to next Error" })
    vim.keymap.set("n", "<leader>gp", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, { buffer = ev.buf, desc = "Go to previous Error" })
  end,
})
