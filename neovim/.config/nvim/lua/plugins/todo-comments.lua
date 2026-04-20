return {
  {
    "folke/todo-comments.nvim",
    lazy = false,
    event = "BufEnter",
    opts = function()
      local p = require("config.palette")
      return {
        signs = true,
        sign_priority = 8,
        keywords = {
          FIX   = { icon = " ", color = "fix",  alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
          TODO  = { icon = " ", color = "todo" },
          HACK  = { icon = " ", color = "hack" },
          WARN  = { icon = " ", color = "warn", alt = { "WARNING" } },
          PERF  = { icon = " ", color = "perf", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
          NOTE  = { icon = " ", color = "info", alt = { "INFO" } },
          TEST  = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
        },
        colors = {
          fix  = { p.red },
          todo = { p.cyan },
          hack = { p.pink },
          warn = { p.yellow },
          perf = { p.purple },
          info = { p.cyan },
          test = { p.orange },
        },
        highlight = {
          before = "",
          keyword = "wide",
          after = "fg",
          pattern = [[.*<(KEYWORDS)\s*:]],
          comments_only = true,
          max_line_len = 400,
          exclude = {},
        },
      }
    end,
    keys = {
      { "<leader>wt", function() Snacks.picker.todo_comments() end,                                          desc = "Todo" },
      { "<leader>wT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end, desc = "Todo/Fix/Fixme" },
      { "n", "]t", function()
        require("todo-comments").jump_next()
      end, { desc = "Next todo comment" } },
      { "n", "[t", function()
        require("todo-comments").jump_prev()
      end, { desc = "Previous todo comment" } }
    }
  }
}
