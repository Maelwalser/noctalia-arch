return {
	"mfussenegger/nvim-jdtls",
	ft = "java",
	dependencies = {
		{ "mfussenegger/nvim-dap", lazy = true },
		{ "rcarriga/nvim-dap-ui", lazy = true },
		{ "microsoft/java-debug", lazy = true },
	},
}
