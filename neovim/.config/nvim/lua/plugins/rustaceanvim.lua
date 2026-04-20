return {
	"mrcjkb/rustaceanvim",
	version = "^6",
	lazy = false,
	ft = { "rust" },
	config = function()
		local codelldb_path, liblldb_path
		local extension_path = vim.fn.expand("$MASON/packages/codelldb/extension/")
		if vim.fn.isdirectory(extension_path) == 1 then
			codelldb_path = extension_path .. "adapter/codelldb"
			local this_os = vim.uv.os_uname().sysname
			if this_os:find("Windows") then
				liblldb_path = extension_path .. "lldb/bin/liblldb.dll"
			else
				liblldb_path = extension_path .. "lldb/lib/" .. (this_os == "Linux" and "liblldb.so" or "liblldb.dylib")
			end
		end

		vim.g.rustaceanvim = {
			tools = {
				float_win_config = { border = "rounded" },
				test_executor = "background",
				enable_clippy = true,
			},
			server = {
				-- Shared on_attach runs via the global LspAttach autocmd
				-- defined in lua/plugins/nvim-lspconfig.lua.
				default_settings = {
					["rust-analyzer"] = {
						cargo = {
							allFeatures = true,
							loadOutDirsFromCheck = true,
							runBuildScripts = true,
						},
						checkOnSave = true,
						check = {
							command = "clippy",
							extraArgs = { "--no-deps" },
						},
						procMacro = {
							enable = true,
							ignored = {
								["async-trait"] = { "async_trait" },
								["napi-derive"] = { "napi" },
								["async-recursion"] = { "async_recursion" },
							},
						},
						inlayHints = {
							bindingModeHints = { enable = true },
							chainingHints = { enable = true },
							closingBraceHints = { enable = true, minLines = 25 },
							closureReturnTypeHints = { enable = "always" },
							lifetimeElisionHints = { enable = "skip_trivial", useParameterNames = true },
							parameterHints = { enable = true },
							rangeExclusiveHints = { enable = true },
							reborrowHints = { enable = "mutable" },
							typeHints = {
								enable = true,
								hideClosureInitialization = false,
								hideNamedConstructor = false,
							},
						},
						diagnostics = { enable = true, experimental = { enable = true } },
						files = { excludeDirs = { ".direnv", ".git", "target", "node_modules" } },
					},
				},
			},
			dap = codelldb_path and {
				adapter = require("rustaceanvim.config").get_codelldb_adapter(codelldb_path, liblldb_path),
				autoload_configurations = true,
			} or { autoload_configurations = true },
		}
	end,
}
