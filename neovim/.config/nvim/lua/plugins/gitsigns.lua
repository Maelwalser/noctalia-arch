-- Git signs
return
{
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },   -- Load when buffer is read
	ft = { "gitcommit", "diff" },             -- Also load for git filetypes
	keys = {
		{ "]c",         desc = "Next hunk" },
		{ "[c",         desc = "Previous hunk" },
		{ "<leader>hs", desc = "Stage hunk" },
		{ "<leader>hr", desc = "Reset hunk" },
		{ "<leader>hS", desc = "Stage buffer" },
		{ "<leader>hu", desc = "Undo stage hunk" },
		{ "<leader>hR", desc = "Reset buffer" },
		{ "<leader>hp", desc = "Preview hunk" },
		{ "<leader>hb", desc = "Blame line" },
		{ "<leader>tb", desc = "Toggle blame" },
		{ "<leader>hd", desc = "Diff this" },
		{ "<leader>hD", desc = "Diff this ~" },
		{ "<leader>td", desc = "Toggle deleted" },
	},
	config = function()
		require("gitsigns").setup({
			on_attach = function(bufnr)
				local gs = package.loaded.gitsigns

				local function map(mode, l, r, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, l, r, opts)
				end

				-- Navigation
				map("n", "]c", function()
					if vim.wo.diff then
						return "]c"
					end
					vim.schedule(function()
						gs.next_hunk()
					end)
					return "<Ignore>"
				end, { expr = true })

				map("n", "[c", function()
					if vim.wo.diff then
						return "[c"
					end
					vim.schedule(function()
						gs.prev_hunk()
					end)
					return "<Ignore>"
				end, { expr = true })

				-- Actions
				map("n", "<leader>hs", gs.stage_hunk)
				map("n", "<leader>hr", gs.reset_hunk)
				map("v", "<leader>hs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end)
				map("v", "<leader>hr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end)
				map("n", "<leader>hS", gs.stage_buffer)
				map("n", "<leader>hu", gs.undo_stage_hunk)
				map("n", "<leader>hR", gs.reset_buffer)
				map("n", "<leader>hp", gs.preview_hunk)
				map("n", "<leader>hb", function()
					gs.blame_line({ full = true })
				end)
				map("n", "<leader>tb", gs.toggle_current_line_blame)
				map("n", "<leader>hd", gs.diffthis)
				map("n", "<leader>hD", function()
					gs.diffthis("~")
				end)
				map("n", "<leader>td", gs.toggle_deleted)

				-- Text object
				map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")
			end,
			-- Reduce resource usage for better performance
			watch_gitdir = {
				interval = 2000,   -- Check git dir every 2 seconds
				follow_files = true
			},
			sign_priority = 6,
			update_debounce = 200,     -- Update signs after 200ms
			max_file_length = 40000,   -- Don't process files longer than this
		})
	end,
}
