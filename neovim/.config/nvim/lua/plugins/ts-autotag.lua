-- Auto completion of HTML tags
return {
	"windwp/nvim-ts-autotag",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	ft = {
		"html",
		"javascript",
		"typescript",
		"javascriptreact",
		"typescriptreact",
		"svelte",
		"vue",
		"tsx",
		"jsx",
	},
	config = function()
		require("nvim-ts-autotag").setup({
			filetypes = {
				'html', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'svelte', 'vue', 'tsx', 'jsx',
			},
			skip_tags = {
				'area',
				'base',
				'br',
				'col',
				'command',
				'embed',
				'hr',
				'img',
				'slot',
				'input',
				'keygen',
				'link',
				'meta',
				'param',
				'source',
				'track',
				'wbr',
				'menuitem',
			}	
		})	
	end
}
