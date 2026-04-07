return {
	-- LSP Configuration
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	cmd = { "LspInfo", "LspInstall", "LspUninstall" },
	dependencies = {
		-- LSP Management
		{ "williamboman/mason.nvim",                   cmd = "Mason", build = ":MasonUpdate" },
		{ "williamboman/mason-lspconfig.nvim",         lazy = true },

		-- Auto-Install LSPs, linters, formatters, debuggers
		{ "WhoIsSethDaniel/mason-tool-installer.nvim", lazy = true },

		-- Useful status updates for LSP
		{ "j-hui/fidget.nvim",                         opts = {},     lazy = true },

		-- Additional lua configuration, makes nvim stuff amazing!
		{ "folke/neodev.nvim",                         opts = {},     ft = "lua" },

		{ "SmiteshP/nvim-navic",                       lazy = true },
	},
	config = function()
		require("mason").setup({
			PATH = "prepend",
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
				border = "rounded",
				width = 0.8,
				height = 0.8,
			},
			registries = {
				"github:mason-org/mason-registry",
				"github:Crashdummyy/mason-registry",
			},
		})

		local lspconfig = require("lspconfig")
		local util = require("lspconfig.util")
		local capabilities = require("cmp_nvim_lsp").default_capabilities()

		-- Common on_attach function
		local common_on_attach = function(client, bufnr)
			vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

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
			vim.keymap.set("n", "<leader>f", function()
				vim.lsp.buf.format({ async = true })
			end, opts)

			-- Keybindings from your init.lua (LSP section)
			vim.keymap.set("n", "<leader>gg", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
			vim.keymap.set("n", "<leader>gD", "<cmd>lua vim.lsp.buf.declaration()<CR>", opts)
			vim.keymap.set("n", "<leader>gI", "<cmd>lua vim.lsp.buf.implementation()<CR>", opts)
			vim.keymap.set("n", "<leader>gt", "<cmd>lua vim.lsp.buf.type_definition()<CR>", opts)
			vim.keymap.set("n", "<leader>gr", "<cmd>lua vim.lsp.buf.references()<CR>", opts)
			vim.keymap.set("n", "<leader>gs", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
			vim.keymap.set("n", "<leader>rr", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
			vim.keymap.set({ "n", "v" }, "<leader>ga", vim.lsp.buf.code_action, opts)
			vim.keymap.set("n", "<leader>gl", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)
			vim.keymap.set("n", "<leader>gp", function() vim.diagnostic.jump({count=-1, float=true}) end, opts)
			vim.keymap.set("n", "<leader>gn", function() vim.diagnostic.jump({count=1, float=true}) end, opts)
			vim.keymap.set("n", "<leader>tr", "<cmd>lua vim.lsp.buf.document_symbol()<CR>", opts)

			if client.server_capabilities.documentSymbolProvider then
				local navic_ok, navic = pcall(require, "nvim-navic")
				if navic_ok then
					local is_navic_attached = false
					for _, existing_client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
						if navic.is_attached(bufnr, existing_client.id) then
							is_navic_attached = true
							break
						end
					end
					if not is_navic_attached then
						navic.attach(client, bufnr)
					end
				end
			end
		end

		local mason_lspconfig = require("mason-lspconfig")

		mason_lspconfig.setup({
			ensure_installed = {
				"jdtls",
				"lua_ls",
				"pyright",
				"gopls",
				"bashls",
				"cssls",
				"html",
				"marksman",
				"tailwindcss",
				"yamlls",
				"jsonls",
				"ast_grep",
				"ruff",
				"vtsls",
			},
			auto_installation = true,
			handlers = {
				["vtsls"] = function()
					lspconfig.vtsls.setup({
						capabilities = capabilities,
						on_attach = common_on_attach,
						filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
						root_dir = util.root_pattern("package.json", "tsconfig.json", "jsconfig.json", ".git"),
					})
				end,
				["lua_ls"] = function()
					lspconfig.lua_ls.setup({
						capabilities = capabilities,
						on_attach = common_on_attach,
						settings = {
							Lua = {
								diagnostics = {
									globals = { "vim" },
								},
							},
						},
					})
				end,
				["jdtls"] = function() end,

				["gopls"] = function()
					lspconfig.gopls.setup({
						capabilities = capabilities,
						on_attach = common_on_attach,
						filetypes = { "go", "gomod", "gowork", "gotmpl" },
						root_dir = util.root_pattern("go.work", "go.mod", ".git"),
						settings = {
							gopls = {
								gofumpt = true,
								codelenses = {
									gc_details = false,
									generate = true,
									regenerate_cgo = true,
									run_govulncheck = true,
									test = true,
									tidy = true,
									upgrade_dependency = true,
									vendor = true,
								},
								hints = {
									assignVariableTypes = true,
									compositeLiteralFields = true,
									compositeLiteralTypes = true,
									constantValues = true,
									functionTypeParameters = true,
									parameterNames = true,
									rangeVariableTypes = true,
								},
								analyses = {
									unusedparams = true,
									nilness = true,
									unusedwrite = true,
									shadow = true,
								},
								staticcheck = true,
								completeUnimported = true,
								usePlaceholders = true,
							},
						},

					})
				end,

				["pyright"] = function()
					lspconfig.pyright.setup({
						capabilities = capabilities,
						on_attach = common_on_attach,
						on_init = function(client)
							-- Determine the workspace path
							local path = client.workspace_folders and client.workspace_folders[1] and client.workspace_folders[1].name
							local venv = vim.env.VIRTUAL_ENV

							-- 1. Check if a virtual environment is activated in the shell
							if venv then
								client.config.settings.python.pythonPath = venv .. "/bin/python"
								-- 2. Fallback to checking for a local '.venv' directory in the project root
							elseif path then
								local local_venv = path .. "/.venv/bin/python"
								if vim.fn.executable(local_venv) == 1 then
									client.config.settings.python.pythonPath = local_venv
								end
							end

							-- Notify Pyright of the updated configuration
							client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
							return true
						end,
						settings = {
							python = {
								analysis = {
									autoSearchPaths = true,
									useLibraryCodeForTypes = true,
									diagnosticMode = "openFilesOnly",
								},
							},
						},
					})
				end,
				["ast_grep"] = function()
					lspconfig.ast_grep.setup({
						capabilities = capabilities,
						on_attach = common_on_attach,
					})
				end,

				function(server_name) lspconfig[server_name].setup({ capabilities = capabilities, on_attach = common_on_attach, })
				end,
			},
		})

		if pcall(require, "fidget") then
			require("fidget").setup({})
		end

		local open_floating_preview_orig = vim.lsp.util.open_floating_preview
		function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
			opts = opts or {}
			opts.border = opts.border or "rounded"
			return open_floating_preview_orig(contents, syntax, opts, ...)
		end

		local mason_tool_installer = require("mason-tool-installer")
		mason_tool_installer.setup({
			ensure_installed = {
				-- Debuggers
				"java-debug-adapter",
				"java-test",
				"go-debug-adapter",
				"js-debug-adapter",
				-- Formatters
				"goimports",
				"shfmt",
				"prettier",
				"prettierd",
				"black",
				"isort",
				"stylua",
				"taplo",
				-- Linters
				"eslint_d",
				"jsonlint",
				"yamllint",
				"yamlfix",
				"shellcheck",
				"hadolint",
				"golangci-lint",
				"ruff",
				"checkstyle",
				"markdownlint",
				-- Go tools
				"gomodifytags",
				"impl",
				-- Other
				"jq",
			},
			auto_update = true,
			run_on_start = true,
		})
	end,
}
