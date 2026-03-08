return {
	"L3MON4D3/LuaSnip",
	lazy = true,
	version = "v2.*", --
	-- install jsregexp (optional!).
	build = "make install_jsregexp",
	dependencies = { { "rafamadriz/friendly-snippets", lazy = true }, },
	config = function()
		local luasnip = require("luasnip")

		-- Simple minimal setup to avoid slow startup
		luasnip.config.setup({
			history = true,
			update_events = "TextChanged,TextChangedI",
			enable_autosnippets = true,
			ext_opts = {
				[require("luasnip.util.types").choiceNode] = {
					active = {
						virt_text = { { "●", "GruvboxOrange" } },
					},
				},
			},
		})

		-- Load snippets lazily when entering insert mode for the first time
		vim.api.nvim_create_autocmd("InsertEnter", {
			once = true,
			callback = function()
				-- Only do this once
				vim.schedule(function()
					require("luasnip.loaders.from_lua").load({ paths = "~/.config/nvim/snippets" })
					require("luasnip.loaders.from_vscode").lazy_load()
				end)
			end,
		})
	end
}
