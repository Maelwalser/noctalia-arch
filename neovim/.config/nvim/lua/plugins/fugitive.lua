return
{
	"tpope/vim-fugitive",
	cmd = { "Git", "Gwrite", "Gread", "Gdiffsplit", "Gvdiffsplit" },   -- Load on git commands
	keys = {
		{ "<leader>gs", "<cmd>Git<CR>", desc = "Git status" },
	},
}
