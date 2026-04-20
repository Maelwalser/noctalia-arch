return {
	"saghen/blink.cmp",
	version = "^1",
	event = { "InsertEnter", "CmdlineEnter" },
	dependencies = {
		{
			"L3MON4D3/LuaSnip",
			build = "make install_jsregexp",
			dependencies = { "rafamadriz/friendly-snippets" },
			config = function()
				require("luasnip.loaders.from_vscode").lazy_load()
			end,
		},
	},
	opts = {
		keymap = {
			preset = "none",
			["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "hide" },
			["<CR>"] = { "accept", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-n>"] = { "select_next", "fallback" },
			["<C-p>"] = { "select_prev", "fallback" },
			["<C-d>"] = { "scroll_documentation_down", "fallback" },
			["<C-f>"] = { "scroll_documentation_up", "fallback" },
			["<Tab>"] = { "snippet_forward", "fallback" },
			["<S-Tab>"] = { "snippet_backward", "fallback" },
		},
		appearance = {
			nerd_font_variant = "mono",
		},
		completion = {
			accept = { auto_brackets = { enabled = true } },
			list = { selection = { preselect = false, auto_insert = false } },
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 200,
				window = { border = "rounded" },
			},
			menu = {
				border = "rounded",
				draw = {
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon", "label", gap = 1 },
						{ "kind" },
					},
				},
			},
			ghost_text = { enabled = true },
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
			providers = {
				lsp = { score_offset = 1000 },
				snippets = { score_offset = 750 },
				buffer = { score_offset = 500 },
				path = { score_offset = 250 },
			},
		},
		snippets = { preset = "luasnip" },
		signature = { enabled = true, window = { border = "rounded" } },
		cmdline = {
			enabled = true,
			keymap = {
				preset = "inherit",
				["<CR>"] = { "accept_and_enter", "fallback" },
			},
			completion = { menu = { auto_show = true } },
		},
		fuzzy = { implementation = "prefer_rust_with_warning" },
	},
	opts_extend = { "sources.default" },
}
