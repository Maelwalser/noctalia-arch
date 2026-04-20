return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	cmd = { "LspInfo", "LspInstall", "LspUninstall" },
	dependencies = {
		{ "williamboman/mason.nvim",                   cmd = "Mason", build = ":MasonUpdate" },
		{ "williamboman/mason-lspconfig.nvim",         lazy = true },
		{ "WhoIsSethDaniel/mason-tool-installer.nvim", lazy = true },
		{ "j-hui/fidget.nvim",                         opts = {},     lazy = true },
		{ "folke/neodev.nvim",                         opts = {},     ft = "lua" },
		{ "SmiteshP/nvim-navic",                       lazy = true },
		{ "b0o/SchemaStore.nvim",                      lazy = true,   version = false },
		{ "saghen/blink.cmp" },
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

		local on_attach = require("config.lsp-on-attach").on_attach

		local capabilities
		local ok_blink, blink = pcall(require, "blink.cmp")
		if ok_blink and blink.get_lsp_capabilities then
			capabilities = blink.get_lsp_capabilities()
		else
			capabilities = vim.lsp.protocol.make_client_capabilities()
		end

		-- --- Nvim 0.11+ vim.lsp.config API -----------------------------------
		-- Default capabilities apply to every server. We intentionally do NOT
		-- set on_attach here because nvim-lspconfig's shipped lsp/<server>.lua
		-- files define their own on_attach, and the merge overrides ours. The
		-- LspAttach autocmd below is the reliable place to run our on_attach
		-- for every client regardless of what the per-server config does.
		vim.lsp.config("*", {
			capabilities = capabilities,
			root_markers = { ".git" },
		})

		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
			callback = function(ev)
				local client = vim.lsp.get_client_by_id(ev.data.client_id)
				if client then on_attach(client, ev.buf) end
			end,
		})

		local ts_inlay_hints = {
			parameterNames = { enabled = "literals" },
			parameterTypes = { enabled = true },
			variableTypes = { enabled = false },
			propertyDeclarationTypes = { enabled = true },
			functionLikeReturnTypes = { enabled = true },
			enumMemberValues = { enabled = true },
		}

		vim.lsp.config("vtsls", {
			settings = {
				complete_function_calls = true,
				vtsls = {
					enableMoveToFileCodeAction = true,
					autoUseWorkspaceTsdk = true,
					experimental = { completion = { enableServerSideFuzzyMatch = true } },
				},
				typescript = {
					updateImportsOnFileMove = { enabled = "always" },
					suggest = { completeFunctionCalls = true },
					inlayHints = ts_inlay_hints,
					preferences = { importModuleSpecifier = "non-relative" },
				},
				javascript = {
					updateImportsOnFileMove = { enabled = "always" },
					suggest = { completeFunctionCalls = true },
					inlayHints = ts_inlay_hints,
				},
			},
		})

		vim.lsp.config("lua_ls", {
			settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
					hint = { enable = true },
					workspace = { checkThirdParty = false },
				},
			},
		})

		vim.lsp.config("gopls", {
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
						useany = true,
					},
					staticcheck = true,
					completeUnimported = true,
					usePlaceholders = true,
					semanticTokens = true,
				},
			},
		})

		vim.lsp.config("pyright", {
			on_init = function(client)
				local path = client.workspace_folders
					and client.workspace_folders[1]
					and client.workspace_folders[1].name
				local venv = vim.env.VIRTUAL_ENV
				if venv then
					client.config.settings.python.pythonPath = venv .. "/bin/python"
				elseif path then
					local local_venv = path .. "/.venv/bin/python"
					if vim.fn.executable(local_venv) == 1 then
						client.config.settings.python.pythonPath = local_venv
					end
				end
				client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
				return true
			end,
			settings = {
				python = {
					analysis = {
						autoSearchPaths = true,
						useLibraryCodeForTypes = true,
						diagnosticMode = "openFilesOnly",
						typeCheckingMode = "basic",
						-- Defer lint/style diagnostics to ruff
						diagnosticSeverityOverrides = {
							reportUnusedImport = "none",
							reportUnusedVariable = "none",
							reportUnusedFunction = "none",
							reportDuplicateImport = "none",
						},
					},
				},
			},
		})

		-- Let pyright own hover; ruff owns lint/fix/organize-imports.
		-- Doing this in a ruff-scoped LspAttach autocmd keeps the single
		-- shared on_attach path intact.
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("UserRuffDisableHover", { clear = true }),
			callback = function(ev)
				local client = vim.lsp.get_client_by_id(ev.data.client_id)
				if client and client.name == "ruff" then
					client.server_capabilities.hoverProvider = false
				end
			end,
		})

		vim.lsp.config("jsonls", {
			settings = {
				json = {
					schemas = require("schemastore").json.schemas(),
					validate = { enable = true },
				},
			},
		})

		vim.lsp.config("yamlls", {
			settings = {
				yaml = {
					schemaStore = { enable = false, url = "" },
					schemas = require("schemastore").yaml.schemas(),
					validate = true,
					format = { enable = true },
					keyOrdering = false,
				},
			},
		})

		-- taplo + ast_grep just use the defaults (capabilities + on_attach)
		vim.lsp.config("taplo", {})
		vim.lsp.config("ast_grep", {})

		-- --- mason-lspconfig 2.0 automatic_enable ----------------------------
		require("mason-lspconfig").setup({
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
				"taplo",
			},
			auto_installation = true,
			-- automatic_enable calls vim.lsp.enable() for every installed server,
			-- picking up the vim.lsp.config() merges above. Exclude servers we
			-- own ourselves or want to avoid duplicating.
			automatic_enable = { exclude = { "jdtls", "rust_analyzer", "ts_ls" } },
		})

		if pcall(require, "fidget") then
			require("fidget").setup({})
		end

		require("mason-tool-installer").setup({
			ensure_installed = {
				"rust-analyzer",
				-- Debuggers
				"java-debug-adapter",
				"java-test",
				"go-debug-adapter",
				"js-debug-adapter",
				"codelldb",
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
				-- Pinned: the mason-registry tracks ruff 0.15.11 which was
				-- yanked from PyPI; 0.15.10 is the latest working release.
				-- auto_update=false prevents the global auto_update from
				-- trying to re-fetch the broken 0.15.11 on every boot.
				{ "ruff", version = "0.15.10", auto_update = false },
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
