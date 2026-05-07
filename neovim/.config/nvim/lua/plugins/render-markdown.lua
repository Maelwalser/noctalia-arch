return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = {
		{ "nvim-treesitter/nvim-treesitter", lazy = true },
		{ "echasnovski/mini.icons",          lazy = true },
	},
	ft = { "markdown" },
	opts = {
		file_types = { "markdown" },
		heading = {
			icons = {},
		},
		render_modes = true,
		pipe_table = {
			preset = "round",
			style = "full",
			cell = "padded",
			border_virtual = true,
			alignment_indicator = "━",
		},
		latex = {
			enabled = true,
			converter = "latex2text",
		},
	},
}
