return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { 
		{"nvim-treesitter/nvim-treesitter", lazy = true},
		{"echasnovski/mini.icons", lazy = true}
	},
	lazy = true,
	opts = {
		heading = {
			icons = {},
		},
		render_modes = true,
	},
}
