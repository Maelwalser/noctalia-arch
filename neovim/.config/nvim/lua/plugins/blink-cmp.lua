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
				window = { border = "single" },
			},
			menu = {
				border = "single",
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
		signature = { enabled = true, window = { border = "single" } },
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
	config = function(_, opts)
		require("blink.cmp").setup(opts)

		local p = require("config.palette")
		local set = function(name, val) vim.api.nvim_set_hl(0, name, val) end

		set("BlinkCmpMenu",           { fg = p.fg, bg = p.bg_alt })
		set("BlinkCmpMenuBorder",     { fg = p.border, bg = p.bg_alt })
		set("BlinkCmpMenuSelection",  { fg = p.cyan, bg = p.selection, bold = true })
		set("BlinkCmpScrollBarThumb", { bg = p.border })
		set("BlinkCmpScrollBarGutter",{ bg = p.bg_alt })
		set("BlinkCmpLabel",          { fg = p.fg })
		set("BlinkCmpLabelMatch",     { fg = p.magenta, bold = true })
		set("BlinkCmpLabelDeprecated",{ fg = p.fg_dim, strikethrough = true })
		set("BlinkCmpGhostText",      { fg = p.fg_dim, italic = true })
		set("BlinkCmpDoc",            { fg = p.fg, bg = p.bg_float })
		set("BlinkCmpDocBorder",      { fg = p.border, bg = p.bg_float })
		set("BlinkCmpSignatureHelp",  { fg = p.fg, bg = p.bg_float })
		set("BlinkCmpSignatureHelpBorder", { fg = p.border, bg = p.bg_float })
		set("BlinkCmpSignatureHelpActiveParameter", { fg = p.cyan, bold = true })

		-- Kind icons (mirrors the in-buffer syntax role map:
		-- function=blue, type=yellow, keyword=purple, field=cyan,
		-- string=green, number/const=orange, accent=pink)
		local kinds = {
			Function      = p.blue,
			Method        = p.blue,
			Constructor   = p.yellow,
			Keyword       = p.purple,
			Operator      = p.cyan,
			Variable      = p.fg,
			Field         = p.cyan,
			Property      = p.cyan,
			Class         = p.yellow,
			Interface     = p.yellow,
			Struct        = p.yellow,
			Enum          = p.yellow,
			EnumMember    = p.orange,
			Module        = p.magenta,
			Namespace     = p.magenta,
			Package       = p.magenta,
			Constant      = p.orange,
			Number        = p.orange,
			Boolean       = p.orange,
			String        = p.green,
			Text          = p.green,
			Snippet       = p.pink,
			File          = p.cyan,
			Folder        = p.cyan,
			Reference     = p.teal,
			Color         = p.pink,
			Event         = p.orange,
			Unit          = p.orange,
			Value         = p.orange,
			TypeParameter = p.yellow,
		}
		for k, fg in pairs(kinds) do
			set("BlinkCmpKind" .. k, { fg = fg, bg = "NONE" })
		end
		set("BlinkCmpKind", { fg = p.fg_dim, bg = "NONE" })
	end,
}
