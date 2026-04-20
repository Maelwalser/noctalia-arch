return {
	"aznhe21/actions-preview.nvim",
	event = "LspAttach",
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = function()
		require("actions-preview").setup({
			backend = { "telescope" },
			diff = { ctxlen = 3 },
			telescope = require("telescope.themes").get_dropdown({ winblend = 10 }),
		})
	end,
}
