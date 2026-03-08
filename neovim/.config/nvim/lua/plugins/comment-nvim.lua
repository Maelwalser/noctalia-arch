return {
	"numToStr/Comment.nvim",
	keys = {
		{ "gc", mode = { "n", "v" }, desc = "Comment toggle linewise" },
		{ "gb", mode = { "n", "v" }, desc = "Comment toggle blockwise" },
	},
	config = function()
		require("Comment").setup({
			ignore = "^$",
			pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
		})
	end
}
