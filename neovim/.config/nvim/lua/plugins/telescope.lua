return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.8",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-ui-select.nvim",
		},
		cmd = "Telescope",
		keys = { -- Load on key presses
			{ "<leader>ff", desc = "(F)ind (F)iles" },
			{ "<leader>fg", desc = "(F)ind (G)it files" },
			{ "<leader>ft", desc = "[F]ind by [T]ext" },
			{ "<leader>fD", desc = "(F)ind (D)iagnostics" },
			{ "<leader>fd", desc = "(F)ind (D)iagnostics in buffer" },
			{ "<leader>fr", desc = "(F)ind (R)esume" },
			{ "<leader>f.", desc = '[F]ind Recent Files ("." for repeat)' },
			{ "<leader>fb", desc = "[F]ind Existing [B]uffers" },
			{ "<leader>cd", desc = "(F)ind project (p)folders" },
		},
		config = function()
			local telescope = require("telescope")
			local actions = require("telescope.actions")
			local actions_state = require("telescope.actions.state")
			local builtin = require("telescope.builtin")

			local oil_ok, oil = pcall(require, "oil")

			local function find_and_change_directory()
				builtin.find_files({
					prompt_title = "< Change Working Directory >",
					previewer = false,
					find_command = { "fd", "--type", "d", "--hidden", "--exclude", ".git" },
					attach_mappings = function(prompt_bufnr, map)
						local function change_cwd()
							local selection = actions_state.get_selected_entry()
							actions.close(prompt_bufnr)

							if selection then
								local new_dir = vim.fn.fnamemodify(selection.value, ":p")


								-- tell oil.nvim to open the new directory
								if oil_ok then
									oil.open(new_dir)
								end
							end
						end

						map("i", "<CR>", change_cwd)
						map("n", "<CR>", change_cwd)
						return true
					end,
				})
			end

			-- Keymaps
			vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "(F)ind (F)iles" })
			vim.keymap.set("n", "<leader>fg", builtin.git_files, { desc = "(F)ind (G)it files" })
			vim.keymap.set("n", "<leader>ft", builtin.live_grep, { desc = "[F]ind by [T]ext" })
			vim.keymap.set("n", "<leader>fD", function() builtin.diagnostics({ severity = vim.diagnostic.severity.ERROR }) end,
				{ desc = "(F)ind (E)rror Diagnostics" })
			vim.keymap.set("n", "<leader>fd", function()
				builtin.diagnostics({ bufnr = 0, previewer = false, severity = vim.diagnostic.severity.ERROR })
			end, { desc = "(F)ind (E)rror Diagnostics in buffer" })
			-- vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "(F)ind (R)esume" })
			vim.keymap.set("n", "<leader>f.", builtin.oldfiles, { desc = '[F]ind Recent Files ("." for repeat)' })
			vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "[F]ind Existing [B]uffers" })
			vim.keymap.set("n", "<leader>cd", find_and_change_directory, { desc = "[C]hange [D]irectory" })

			-- Configuration
			telescope.setup({
				defaults = {
					file_ignore_patterns = { "bin", ".gitignore", "node_modules", "PackageCache", ".git", "/build" },
					mappings = {
						i = {
							["<C-j>"] = actions.move_selection_next,
							["<C-k>"] = actions.move_selection_previous,
							["<C-n>"] = actions.cycle_history_next,
							["<C-p>"] = actions.cycle_history_prev,
						},
						n = {
							["<C-j>"] = actions.move_selection_next,
							["<C-k>"] = actions.move_selection_previous,
						},
					},
					path_display = {
						shorten = {
							len = 3,
							exclude = { 1, -1 },
						},
						truncate = true,
					},
					dynamic_preview_title = true,
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
					fzf = {
						fuzzy = true,             -- false will only do exact matching
						override_generic_sorter = true, -- override the generic sorter
						override_file_sorter = true, -- override the file sorter
						case_mode = "smart_case", -- or "ignore_case" or "respect_case"
					},
				},
				mappings = {
					i = {
						["<C-n>"] = actions.cycle_history_next,
						["<C-p>"] = actions.cycle_history_prev,
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
					},
				},
			})

			-- Load extensions
			vim.api.nvim_create_autocmd("User", {
				pattern = "TelescopeCommand",
				once = true,
				callback = function()
					pcall(telescope.load_extension, "ui-select")
					pcall(telescope.load_extension, "noice")
					pcall(function()
						require("telescope").extensions.dap.configurations()
					end)
				end,
			})
		end,
	},
}
