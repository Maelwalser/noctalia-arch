return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	cmd = { 'ConformInfo' },
	keys = {
		{
			'<leader>f',
			function()
				require('conform').format { async = true, lsp_fallback = true }
			end,
			mode = '',
			desc = '[F]ormat buffer',
		},
	},
	opts = {
		format_on_save = function(bufnr)
			local disable_filetypes = { c = true, cpp = true }
			return {
				timeout_ms = 1000,
				lsp_fallback = true,
			}
		end,
	},

	config = function()
		vim.g.autoformat = true

		-- Load formatters on demand per filetype
		local formatters_by_ft = {
			css = { "prettierd", "prettier", stop_after_first = true },
			graphql = { "prettierd", "prettier", stop_after_first = true },
			html = { "prettierd", "prettier", stop_after_first = true },
			javascript = { "prettierd", "prettier", stop_after_first = true },
			javascriptreact = { "prettierd", "prettier", stop_after_first = true },
			typescript = { "prettierd", "prettier", stop_after_first = true },
			typescriptreact = { "prettierd", "prettier", stop_after_first = true },
			json = { "prettierd", "prettier", stop_after_first = true },
			jsonc = { "prettierd", "prettier", stop_after_first = true },
			markdown = { "prettierd", "prettier", stop_after_first = true },
			python = { "isort", "black" },
			java = { "prettier-java" },
			scss = { "prettier" },
			sh = { "shfmt" },
			bash = { "shfmt" },
			lua = { "stylua" },
			templ = { "templ" },
			toml = { "taplo" },
			yaml = { "prettier" },
			go = { "goimports", "gofmt" },
			rust = { "rustfmt", lsp_format = "fallback" },
			["_"] = { "trim_whitespace" },
		}

		-- Only load formatters for the current filetype
		local loaded_formatters = {}
		local function get_formatters_for_ft(ft)
			if loaded_formatters[ft] then
				return loaded_formatters[ft]
			end

			loaded_formatters[ft] = formatters_by_ft[ft] or {}
			return loaded_formatters[ft]
		end

		require("conform").setup({
			-- Dynamically load formatters only when needed
			formatters_by_ft = setmetatable({}, {
				__index = function(_, key)
					return get_formatters_for_ft(key)
				end
			}),
			-- Set the log level. Use `:ConformInfo` to see the location of the log file
			log_level = vim.log.levels.ERROR,

			-- notify when a formatter errors
			notify_on_error = true,
		})
	end,
}
