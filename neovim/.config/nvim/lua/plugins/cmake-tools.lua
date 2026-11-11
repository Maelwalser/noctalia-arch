return {
	"Civitasv/cmake-tools.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	ft = { "c", "cpp", "cmake" },
	cmd = {
		"CMakeGenerate",
		"CMakeBuild",
		"CMakeRun",
		"CMakeDebug",
		"CMakeRunTest",
		"CMakeSelectBuildType",
		"CMakeSelectBuildTarget",
		"CMakeSelectLaunchTarget",
		"CMakeSelectConfigurePreset",
	},
	keys = {
		{ "<leader>mg", "<cmd>CMakeGenerate<CR>", desc = "CMake generate" },
		{ "<leader>mb", "<cmd>CMakeBuild<CR>", desc = "CMake build" },
		{ "<leader>mr", "<cmd>CMakeRun<CR>", desc = "CMake run" },
		{ "<leader>md", "<cmd>CMakeDebug<CR>", desc = "CMake debug" },
		{ "<leader>mt", "<cmd>CMakeRunTest<CR>", desc = "CMake run tests (ctest)" },
		{ "<leader>ml", "<cmd>CMakeSelectLaunchTarget<CR>", desc = "CMake select launch target" },
		{ "<leader>mT", "<cmd>CMakeSelectBuildTarget<CR>", desc = "CMake select build target" },
		{ "<leader>mv", "<cmd>CMakeSelectBuildType<CR>", desc = "CMake select build type" },
		{ "<leader>ma", "<cmd>CMakeLaunchArgs<CR>", desc = "CMake launch arguments" },
	},
	opts = {
		cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=1" },
		cmake_build_directory = "build/${variant:buildType}",
		-- clangd looks for compile_commands.json at the project root; the link
		-- follows whichever build type is active.
		cmake_compile_commands_options = {
			action = "soft_link",
			target = vim.uv.cwd,
		},
		-- The adapter itself is defined in lua/config/dap/cpp.lua.
		cmake_dap_configuration = {
			name = "cpp",
			type = "codelldb",
			request = "launch",
			stopOnEntry = false,
			runInTerminal = true,
			console = "integratedTerminal",
		},
	},
}
