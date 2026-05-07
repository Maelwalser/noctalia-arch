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

			format_on_save = function(bufnr)
				if vim.g.autoformat == false or vim.b[bufnr].autoformat == false then
					return
				end
				local disable_filetypes = { c = true, cpp = true }
				if disable_filetypes[vim.bo[bufnr].filetype] then
					return
				end
				return {
					timeout_ms = 1000,
					lsp_format = "fallback",
				}
			end,
		})

		-- Toggle format-on-save globally or per-buffer
		vim.api.nvim_create_user_command("FormatDisable", function(args)
			if args.bang then
				vim.b.autoformat = false
			else
				vim.g.autoformat = false
			end
		end, { bang = true, desc = "Disable format-on-save (use ! for buffer-local)" })

		vim.api.nvim_create_user_command("FormatEnable", function()
			vim.b.autoformat = nil
			vim.g.autoformat = true
		end, { desc = "Re-enable format-on-save" })
	end,
}
