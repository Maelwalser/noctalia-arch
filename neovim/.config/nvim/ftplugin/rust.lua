vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4
vim.opt_local.expandtab = true
vim.opt_local.colorcolumn = "100"

local map = function(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { buffer = true, silent = true, desc = desc })
end

-- rustaceanvim exposes richer actions (macro expansion, explain error, etc.) than the vanilla LSP API
vim.keymap.set({ "n", "v" }, "<leader>ga", function()
	vim.cmd.RustLsp("codeAction")
end, { buffer = true, silent = true, desc = "Rust code action (rustaceanvim)" })

map("<leader>gg", function() vim.cmd.RustLsp({ "hover", "actions" }) end, "Rust hover actions")
map("<leader>tt", "<cmd>RustLsp testables<CR>", "Rust testables")
map("<leader>tR", "<cmd>RustLsp runnables<CR>", "Rust runnables")
map("<leader>re", "<cmd>RustLsp explainError<CR>", "Explain error")
map("<leader>rm", "<cmd>RustLsp expandMacro<CR>", "Expand macro")
map("<leader>rp", "<cmd>RustLsp parentModule<CR>", "Parent module")
map("<leader>rc", "<cmd>RustLsp openCargo<CR>", "Open Cargo.toml")
map("<leader>rd", "<cmd>RustLsp renderDiagnostic<CR>", "Render current diagnostic")
map("<leader>db", "<cmd>RustLsp debuggables<CR>", "Rust debuggables")

-- Jump-to-error helpers consistent with other ftplugins
local function jump_to_error(count)
	vim.diagnostic.jump({ count = count, severity = vim.diagnostic.severity.ERROR, float = true })
end
map("<leader>gn", function() jump_to_error(1) end, "Go to next Rust error")
map("<leader>gp", function() jump_to_error(-1) end, "Go to previous Rust error")
