return {
	"nvim-treesitter/nvim-treesitter-textobjects",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		local ok, textobjects = pcall(require, "nvim-treesitter-textobjects")
		if not ok then return end

		textobjects.setup({
			select = {
				lookahead = true,
				selection_modes = {
					["@parameter.outer"] = "v",
					["@function.outer"] = "V",
					["@class.outer"] = "<c-v>",
				},
				include_surrounding_whitespace = false,
			},
			move = { set_jumps = true },
		})

		local select = require("nvim-treesitter-textobjects.select")
		local move = require("nvim-treesitter-textobjects.move")

		local function sel(query)
			return function() select.select_textobject(query, "textobjects") end
		end

		-- Select
		vim.keymap.set({ "x", "o" }, "af", sel("@function.outer"), { desc = "TS outer function" })
		vim.keymap.set({ "x", "o" }, "if", sel("@function.inner"), { desc = "TS inner function" })
		vim.keymap.set({ "x", "o" }, "ac", sel("@class.outer"),    { desc = "TS outer class" })
		vim.keymap.set({ "x", "o" }, "ic", sel("@class.inner"),    { desc = "TS inner class" })
		vim.keymap.set({ "x", "o" }, "aa", sel("@parameter.outer"), { desc = "TS outer parameter" })
		vim.keymap.set({ "x", "o" }, "ia", sel("@parameter.inner"), { desc = "TS inner parameter" })
		vim.keymap.set({ "x", "o" }, "al", sel("@loop.outer"),      { desc = "TS outer loop" })
		vim.keymap.set({ "x", "o" }, "il", sel("@loop.inner"),      { desc = "TS inner loop" })
		vim.keymap.set({ "x", "o" }, "ai", sel("@conditional.outer"), { desc = "TS outer conditional" })
		vim.keymap.set({ "x", "o" }, "ii", sel("@conditional.inner"), { desc = "TS inner conditional" })

		-- Move
		local function next_start(q) return function() move.goto_next_start(q, "textobjects") end end
		local function next_end(q)   return function() move.goto_next_end(q,   "textobjects") end end
		local function prev_start(q) return function() move.goto_previous_start(q, "textobjects") end end
		local function prev_end(q)   return function() move.goto_previous_end(q,   "textobjects") end end

		vim.keymap.set({ "n", "x", "o" }, "]f", next_start("@function.outer"), { desc = "Next func start" })
		vim.keymap.set({ "n", "x", "o" }, "]F", next_end("@function.outer"),   { desc = "Next func end" })
		vim.keymap.set({ "n", "x", "o" }, "[f", prev_start("@function.outer"), { desc = "Prev func start" })
		vim.keymap.set({ "n", "x", "o" }, "[F", prev_end("@function.outer"),   { desc = "Prev func end" })
		vim.keymap.set({ "n", "x", "o" }, "]c", next_start("@class.outer"),    { desc = "Next class start" })
		vim.keymap.set({ "n", "x", "o" }, "[c", prev_start("@class.outer"),    { desc = "Prev class start" })
		vim.keymap.set({ "n", "x", "o" }, "]a", next_start("@parameter.inner"), { desc = "Next param" })
		vim.keymap.set({ "n", "x", "o" }, "[a", prev_start("@parameter.inner"), { desc = "Prev param" })
	end,
}
