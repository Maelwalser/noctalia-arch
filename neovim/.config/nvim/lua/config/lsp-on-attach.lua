local M = {}

local doc_highlight_group = vim.api.nvim_create_augroup("LspDocumentHighlight", { clear = false })

local function setup_doc_highlight(client, bufnr)
	if not client:supports_method("textDocument/documentHighlight") then return end
	vim.api.nvim_clear_autocmds({ group = doc_highlight_group, buffer = bufnr })
	vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
		group = doc_highlight_group,
		buffer = bufnr,
		callback = vim.lsp.buf.document_highlight,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = doc_highlight_group,
		buffer = bufnr,
		callback = vim.lsp.buf.clear_references,
	})
end

local function setup_inlay_hints(client, bufnr)
	if client:supports_method("textDocument/inlayHint") then
		-- Defer one tick: some servers (vtsls) negotiate inlayHintProvider
		-- slightly after on_attach fires. Enabling on the next event-loop tick
		-- is reliable across servers.
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
			end
		end)
	end
end

local function setup_keymaps(client, bufnr)
	local opts = { buffer = bufnr, noremap = true, silent = true }

	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
	vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
	vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)

	vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
	vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
	vim.keymap.set("n", "<leader>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, opts)

	vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format({ async = true }) end, opts)

	vim.keymap.set("n", "<leader>gg", vim.lsp.buf.hover, opts)
	vim.keymap.set("n", "<leader>gD", vim.lsp.buf.declaration, opts)
	vim.keymap.set("n", "<leader>gI", vim.lsp.buf.implementation, opts)
	vim.keymap.set("n", "<leader>gt", vim.lsp.buf.type_definition, opts)
	vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, opts)
	vim.keymap.set("n", "<leader>gs", vim.lsp.buf.signature_help, opts)
	vim.keymap.set("n", "<leader>gl", vim.diagnostic.open_float, opts)
	vim.keymap.set("n", "<leader>gp", function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
	vim.keymap.set("n", "<leader>gn", function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)
	vim.keymap.set("n", "<leader>tr", vim.lsp.buf.document_symbol, opts)

	-- Code actions with diff-preview (actions-preview.nvim) + vanilla fallback
	vim.keymap.set({ "n", "v" }, "<leader>ga", function()
		local ok, ap = pcall(require, "actions-preview")
		if ok then ap.code_actions() else vim.lsp.buf.code_action() end
	end, opts)

	-- Rename: live-preview if inc-rename is loaded, else vanilla LSP rename
	vim.keymap.set("n", "<leader>rr", vim.lsp.buf.rename, opts)
	vim.keymap.set("n", "<leader>rn", function()
		if pcall(require, "inc_rename") then
			return ":IncRename " .. vim.fn.expand("<cword>")
		end
		vim.lsp.buf.rename()
	end, { buffer = bufnr, noremap = true, silent = false, expr = true })

	-- Buffer-local inlay-hint toggle
	vim.keymap.set("n", "<leader>ih", function()
		local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
		vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
	end, opts)
end

local function setup_navic(client, bufnr)
	if not client.server_capabilities or not client.server_capabilities.documentSymbolProvider then return end
	local ok, navic = pcall(require, "nvim-navic")
	if not ok then return end
	-- navic.attach is effectively idempotent per (client, buf) via its own guard.
	pcall(navic.attach, client, bufnr)
end

function M.on_attach(client, bufnr)
	vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
	setup_keymaps(client, bufnr)
	setup_inlay_hints(client, bufnr)
	setup_doc_highlight(client, bufnr)
	setup_navic(client, bufnr)
end

return setmetatable(M, {
	__call = function(_, client, bufnr) M.on_attach(client, bufnr) end,
})
